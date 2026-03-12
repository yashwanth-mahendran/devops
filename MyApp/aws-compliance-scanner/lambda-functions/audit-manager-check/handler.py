"""
compliance-check-audit-manager
Verifies that AWS Audit Manager is enabled and has at least one active assessment.
"""
import boto3
import logging
from typing import Any, Dict

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    account_id = event["account_id"]
    region     = event["region"]
    job_id     = event["job_id"]

    logger.info("audit_manager check | job=%s account=%s region=%s", job_id, account_id, region)

    # Audit Manager is only available in certain regions
    SUPPORTED_REGIONS = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-central-1", "ap-southeast-2", "ap-northeast-1",
    ]
    if region not in SUPPORTED_REGIONS:
        return _result(
            "SKIPPED",
            f"Audit Manager not available in {region}",
            account_id, region,
        )

    try:
        am = boto3.client("auditmanager", region_name=region)

        # Check account registration status
        settings_resp = am.get_settings(attribute="ALL")
        am_settings   = settings_resp.get("settings", {})
        status        = am_settings.get("isAwsOrgEnabled") or am_settings.get("snsTopic") is not None

        if not status:
            return _result(
                "FAILED",
                "AWS Audit Manager is not enabled for this account",
                account_id,
                region,
                remediation = (
                    "Enable Audit Manager: "
                    "aws auditmanager register-account --kms-key default "
                    "or via the AWS Console → Audit Manager → Get Started."
                ),
            )

        # Check for active assessments
        assessments = am.list_assessments(status="ACTIVE").get("assessmentMetadata", [])
        if not assessments:
            return _result(
                "FAILED",
                "Audit Manager is enabled but no active assessments found",
                account_id,
                region,
                remediation = (
                    "Create an assessment in Audit Manager using a built-in framework "
                    "(e.g., CIS AWS Foundations, SOC2, HIPAA) or a custom framework."
                ),
            )

        return _result(
            "PASSED",
            f"Audit Manager enabled with {len(assessments)} active assessment(s)",
            account_id, region,
        )

    except am.exceptions.AccessDeniedException as exc:
        return _result("ERROR", f"Access denied: {exc}", account_id, region)
    except Exception as exc:
        logger.exception("audit_manager check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
