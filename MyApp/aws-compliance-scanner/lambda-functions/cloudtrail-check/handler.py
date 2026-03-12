"""
compliance-check-cloudtrail
Verifies CloudTrail multi-region trail is enabled with log file validation.
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

    try:
        ct = boto3.client("cloudtrail", region_name=region)
        trails = ct.describe_trails(includeShadowTrails=False)["trailList"]

        if not trails:
            return _result(
                "FAILED",
                "No CloudTrail trails found in this account",
                account_id, region,
                remediation = (
                    "Create a multi-region trail: "
                    "aws cloudtrail create-trail --name org-trail --s3-bucket-name <bucket> "
                    "--is-multi-region-trail --enable-log-file-validation; "
                    "aws cloudtrail start-logging --name org-trail"
                ),
            )

        issues = []
        for trail in trails:
            name = trail["Name"]
            status = ct.get_trail_status(Name=name)

            if not status.get("IsLogging"):
                issues.append(f"{name}: logging disabled")
            if not trail.get("IsMultiRegionTrail"):
                issues.append(f"{name}: not multi-region")
            if not trail.get("LogFileValidationEnabled"):
                issues.append(f"{name}: log file validation disabled")

        if issues:
            return _result(
                "FAILED",
                f"CloudTrail issues: {'; '.join(issues[:3])}",
                account_id, region,
                remediation = (
                    "Update trail: aws cloudtrail update-trail "
                    "--name <trail> --is-multi-region-trail --enable-log-file-validation; "
                    "aws cloudtrail start-logging --name <trail>"
                ),
            )

        return _result(
            "PASSED",
            f"All {len(trails)} CloudTrail trail(s) are active and multi-region",
            account_id, region,
        )

    except Exception as exc:
        logger.exception("cloudtrail check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
