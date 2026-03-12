"""
Step Functions Invoker Service
Invokes AWS Step Functions to orchestrate compliance checks.

This approach delegates orchestration to Step Functions instead of
managing concurrency and Lambda invocations directly in the application.
"""
import boto3
import json
import logging
from typing import Any, Dict, List, Optional

from opentelemetry import trace
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

from app.config import get_settings

logger   = logging.getLogger(__name__)
settings = get_settings()
tracer   = trace.get_tracer(__name__)

# All registered checks (same as Approach A, for reference)
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


class StepFunctionsInvoker:
    """
    Service to invoke Step Functions for compliance scanning.
    
    Flow:
    1. FastAPI receives scan request
    2. Creates job record in DynamoDB (PENDING)
    3. Invokes Step Functions state machine (ASYNC)
    4. Returns 202 Accepted with job_id
    5. Step Functions orchestrates all Lambda invocations
    6. Step Functions writes results to DynamoDB
    7. Client polls for results
    """

    def __init__(self):
        self._sfn_client = None

    @property
    def sfn_client(self):
        """Lazy-load Step Functions client."""
        if self._sfn_client is None:
            self._sfn_client = boto3.client(
                "stepfunctions",
                region_name=settings.AWS_REGION,
            )
        return self._sfn_client

    def start_scan_execution(
        self,
        job_id: str,
        account_ids: List[str],
        regions: List[str],
        check_ids: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Start a Step Functions execution for the compliance scan.
        
        Args:
            job_id: Unique job identifier
            account_ids: List of AWS account IDs to scan
            regions: List of AWS regions to scan
            check_ids: Optional list of specific checks to run (defaults to all)
        
        Returns:
            Dict with execution ARN and start time
        """
        # Use all checks if none specified
        if not check_ids:
            check_ids = [c["id"] for c in REGISTERED_CHECKS]

        # Propagate OTEL trace context
        carrier: Dict[str, str] = {}
        TraceContextTextMapPropagator().inject(carrier)

        # Build Step Functions input payload
        sfn_input = {
            "job_id": job_id,
            "account_ids": account_ids,
            "regions": regions,
            "checks": check_ids,
            "trace_context": carrier,
        }

        with tracer.start_as_current_span("stepfunctions_start_execution") as span:
            span.set_attribute("job_id", job_id)
            span.set_attribute("state_machine_arn", settings.STEP_FUNCTION_ARN)
            span.set_attribute("num_accounts", len(account_ids))
            span.set_attribute("num_regions", len(regions))
            span.set_attribute("num_checks", len(check_ids))

            try:
                response = self.sfn_client.start_execution(
                    stateMachineArn=settings.STEP_FUNCTION_ARN,
                    name=f"scan-{job_id}",  # Must be unique per execution
                    input=json.dumps(sfn_input),
                )

                logger.info(
                    "Started Step Functions execution job_id=%s execution_arn=%s",
                    job_id,
                    response["executionArn"],
                )

                return {
                    "execution_arn": response["executionArn"],
                    "start_date": response["startDate"].isoformat(),
                }

            except self.sfn_client.exceptions.ExecutionAlreadyExists:
                logger.warning("Execution already exists for job_id=%s", job_id)
                raise ValueError(f"Scan job {job_id} already exists")

            except Exception as exc:
                logger.exception("Failed to start Step Functions execution: %s", exc)
                span.record_exception(exc)
                raise

    def start_sync_execution(
        self,
        job_id: str,
        account_ids: List[str],
        regions: List[str],
        check_ids: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Start a SYNCHRONOUS Step Functions execution (Express Workflow only).
        
        This blocks until the workflow completes, suitable for smaller scans
        where immediate results are needed.
        
        Args:
            job_id: Unique job identifier
            account_ids: List of AWS account IDs to scan
            regions: List of AWS regions to scan
            check_ids: Optional list of specific checks to run
        
        Returns:
            Dict with execution results
        """
        if not check_ids:
            check_ids = [c["id"] for c in REGISTERED_CHECKS]

        carrier: Dict[str, str] = {}
        TraceContextTextMapPropagator().inject(carrier)

        sfn_input = {
            "job_id": job_id,
            "account_ids": account_ids,
            "regions": regions,
            "checks": check_ids,
            "trace_context": carrier,
        }

        with tracer.start_as_current_span("stepfunctions_sync_execution") as span:
            span.set_attribute("job_id", job_id)
            span.set_attribute("sync", True)

            try:
                response = self.sfn_client.start_sync_execution(
                    stateMachineArn=settings.STEP_FUNCTION_ARN,
                    name=f"scan-{job_id}",
                    input=json.dumps(sfn_input),
                )

                status = response["status"]
                span.set_attribute("execution_status", status)

                if status == "SUCCEEDED":
                    output = json.loads(response.get("output", "{}"))
                    return {
                        "status": "COMPLETED",
                        "output": output,
                        "execution_arn": response["executionArn"],
                    }
                else:
                    error = response.get("error", "Unknown")
                    cause = response.get("cause", "Unknown")
                    logger.error(
                        "Sync execution failed job_id=%s error=%s cause=%s",
                        job_id, error, cause,
                    )
                    return {
                        "status": "FAILED",
                        "error": error,
                        "cause": cause,
                        "execution_arn": response["executionArn"],
                    }

            except Exception as exc:
                logger.exception("Failed sync execution: %s", exc)
                span.record_exception(exc)
                raise

    def get_execution_status(self, execution_arn: str) -> Dict[str, Any]:
        """
        Get the status of a Step Functions execution.
        
        Args:
            execution_arn: ARN of the execution to check
        
        Returns:
            Dict with status and optional output/error
        """
        with tracer.start_as_current_span("stepfunctions_describe_execution") as span:
            span.set_attribute("execution_arn", execution_arn)

            try:
                response = self.sfn_client.describe_execution(
                    executionArn=execution_arn,
                )

                status = response["status"]
                result = {
                    "status": status,
                    "start_date": response["startDate"].isoformat(),
                }

                if status == "SUCCEEDED":
                    result["output"] = json.loads(response.get("output", "{}"))
                    result["stop_date"] = response["stopDate"].isoformat()
                elif status in ("FAILED", "TIMED_OUT", "ABORTED"):
                    result["error"] = response.get("error")
                    result["cause"] = response.get("cause")
                    if "stopDate" in response:
                        result["stop_date"] = response["stopDate"].isoformat()

                return result

            except Exception as exc:
                logger.exception("Failed to describe execution: %s", exc)
                span.record_exception(exc)
                raise

    def stop_execution(self, execution_arn: str, cause: str = "User requested") -> bool:
        """
        Stop a running Step Functions execution.
        
        Args:
            execution_arn: ARN of the execution to stop
            cause: Reason for stopping
        
        Returns:
            True if successfully stopped
        """
        try:
            self.sfn_client.stop_execution(
                executionArn=execution_arn,
                cause=cause,
            )
            logger.info("Stopped execution: %s", execution_arn)
            return True
        except Exception as exc:
            logger.exception("Failed to stop execution: %s", exc)
            return False


# Singleton instance
_invoker: Optional[StepFunctionsInvoker] = None


def get_stepfunctions_invoker() -> StepFunctionsInvoker:
    """Get or create the Step Functions invoker singleton."""
    global _invoker
    if _invoker is None:
        _invoker = StepFunctionsInvoker()
    return _invoker


async def run_checks_via_stepfunctions(
    job_id: str,
    account_ids: List[str],
    regions: List[str],
    check_ids: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """
    Trigger compliance checks via Step Functions (async).
    
    This is the main entry point called from the scan router.
    Step Functions handles all orchestration — no FastAPI background tasks needed.
    
    Args:
        job_id: Unique job identifier
        account_ids: AWS accounts to scan
        regions: AWS regions to scan
        check_ids: Specific checks to run (optional)
    
    Returns:
        Dict with execution_arn for tracking
    """
    invoker = get_stepfunctions_invoker()
    return invoker.start_scan_execution(job_id, account_ids, regions, check_ids)
