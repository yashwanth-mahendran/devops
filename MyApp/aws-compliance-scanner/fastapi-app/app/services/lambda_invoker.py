"""
Lambda Invoker Service
Invokes compliance-check Lambda functions concurrently per account/region/check.
"""
import asyncio
import boto3
import json
import logging
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional

from opentelemetry import trace
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

from app.config import get_settings
from app.schemas import CheckResult, CheckStatus

logger   = logging.getLogger(__name__)
settings = get_settings()
tracer   = trace.get_tracer(__name__)

# All registered checks.
# Each entry maps to:   <LAMBDA_FUNCTION_PREFIX>-<check_id>
REGISTERED_CHECKS: List[Dict[str, str]] = [
    {"id": "cfn_drift",               "name": "CloudFormation Stack Drift",          "severity": "HIGH"},
    {"id": "vpc_flow_logs",           "name": "VPC Flow Logs Enabled",               "severity": "HIGH"},
    {"id": "audit_manager_enabled",   "name": "AWS Audit Manager Enabled",           "severity": "MEDIUM"},
    {"id": "s3_encryption",           "name": "S3 Bucket Default Encryption",        "severity": "HIGH"},
    {"id": "iam_mfa_root",            "name": "Root Account MFA Enabled",            "severity": "CRITICAL"},
    {"id": "iam_mfa_users",           "name": "IAM Users MFA Enforced",              "severity": "HIGH"},
    {"id": "cloudtrail_enabled",      "name": "CloudTrail Multi-Region Enabled",     "severity": "HIGH"},
    {"id": "sg_unrestricted_ssh",     "name": "Security Group Unrestricted SSH",     "severity": "CRITICAL"},
    {"id": "rds_encryption",          "name": "RDS Encryption at Rest",              "severity": "HIGH"},
    {"id": "ebs_encryption",          "name": "EBS Volume Encryption",               "severity": "MEDIUM"},
    {"id": "guardduty_enabled",       "name": "GuardDuty Enabled",                   "severity": "HIGH"},
    {"id": "config_recorder",         "name": "AWS Config Recorder Active",          "severity": "MEDIUM"},
    {"id": "secrets_manager_rotation","name": "Secrets Manager Auto-Rotation",       "severity": "MEDIUM"},
    {"id": "ecr_image_scanning",      "name": "ECR Image Scanning on Push",          "severity": "MEDIUM"},
    {"id": "eks_cluster_logging",     "name": "EKS Control Plane Logging",           "severity": "MEDIUM"},
]


def _get_lambda_client(role_arn: Optional[str] = None):
    """Return a boto3 Lambda client, optionally assuming a cross-account role."""
    if role_arn:
        sts    = boto3.client("sts")
        creds  = sts.assume_role(RoleArn=role_arn, RoleSessionName="ComplianceScanner")["Credentials"]
        return boto3.client(
            "lambda",
            region_name=settings.AWS_REGION,
            aws_access_key_id     = creds["AccessKeyId"],
            aws_secret_access_key = creds["SecretAccessKey"],
            aws_session_token     = creds["SessionToken"],
        )
    return boto3.client("lambda", region_name=settings.AWS_REGION)


def _invoke_lambda(
    check: Dict[str, str],
    account_id: str,
    region: str,
    job_id: str,
    trace_context: Dict[str, str],
) -> CheckResult:
    """Synchronous Lambda invocation — runs in ThreadPoolExecutor."""
    function_name = f"{settings.LAMBDA_FUNCTION_PREFIX}-{check['id']}"
    payload = {
        "job_id":        job_id,
        "account_id":    account_id,
        "region":        region,
        "check_id":      check["id"],
        "trace_context": trace_context,
    }

    start = time.time()
    try:
        assume_role_arn = settings.ASSUME_ROLE_ARN_TEMPLATE.format(account_id=account_id)
        client = _get_lambda_client(assume_role_arn)
        response = client.invoke(
            FunctionName   = function_name,
            InvocationType = "RequestResponse",
            Payload        = json.dumps(payload).encode(),
        )
        duration_ms = int((time.time() - start) * 1000)
        body = json.loads(response["Payload"].read())

        if response.get("FunctionError"):
            logger.error("Lambda function error: %s | check=%s account=%s", body, check["id"], account_id)
            return CheckResult(
                check_id    = check["id"],
                check_name  = check["name"],
                account_id  = account_id,
                region      = region,
                status      = CheckStatus.ERROR,
                message     = str(body),
                severity    = check["severity"],
                timestamp   = _now(),
            )

        logger.info("check=%s account=%s region=%s status=%s duration_ms=%d",
                    check["id"], account_id, region, body.get("status"), duration_ms)
        return CheckResult(
            check_id    = check["id"],
            check_name  = check["name"],
            account_id  = account_id,
            region      = region,
            status      = CheckStatus(body.get("status", "ERROR")),
            resource_id = body.get("resource_id"),
            message     = body.get("message", ""),
            remediation = body.get("remediation"),
            severity    = check["severity"],
            timestamp   = _now(),
        )

    except Exception as exc:
        logger.exception("Failed to invoke %s: %s", function_name, exc)
        return CheckResult(
            check_id   = check["id"],
            check_name = check["name"],
            account_id = account_id,
            region     = region,
            status     = CheckStatus.ERROR,
            message    = str(exc),
            severity   = check["severity"],
            timestamp  = _now(),
        )


def _now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


async def run_checks_async(
    job_id:      str,
    account_ids: List[str],
    regions:     List[str],
    check_ids:   Optional[List[str]] = None,
) -> List[CheckResult]:
    """
    Fan-out all checks across all account/region combinations concurrently.
    Uses a ThreadPoolExecutor to bridge sync boto3 calls into async FastAPI.
    """
    checks = REGISTERED_CHECKS
    if check_ids:
        checks = [c for c in REGISTERED_CHECKS if c["id"] in check_ids]

    # Propagate OTEL trace context into Lambda payloads
    carrier: Dict[str, str] = {}
    TraceContextTextMapPropagator().inject(carrier)

    tasks = [
        (check, account_id, region)
        for check      in checks
        for account_id in account_ids
        for region     in regions
    ]

    loop = asyncio.get_event_loop()
    semaphore = asyncio.Semaphore(settings.MAX_CONCURRENT_LAMBDA_CALLS)

    async def bounded_invoke(check, account_id, region):
        async with semaphore:
            return await loop.run_in_executor(
                None, _invoke_lambda, check, account_id, region, job_id, carrier
            )

    with tracer.start_as_current_span("run_checks_async") as span:
        span.set_attribute("job_id",      job_id)
        span.set_attribute("num_checks",  len(checks))
        span.set_attribute("num_accounts",len(account_ids))
        span.set_attribute("num_regions", len(regions))
        results = await asyncio.gather(
            *[bounded_invoke(c, a, r) for c, a, r in tasks],
            return_exceptions=False,
        )

    return list(results)
