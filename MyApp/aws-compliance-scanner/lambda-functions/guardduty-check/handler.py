"""
Compliance Check: GuardDuty Enabled
Verifies that GuardDuty is enabled and has active detector(s) in the target account/region.
"""

import json
import logging
import boto3
from botocore.exceptions import ClientError, EndpointResolutionError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_boto3_session(event: dict) -> boto3.Session:
    """Assume cross-account role if credentials provided, else use current role."""
    role_arn = event.get("role_arn")
    external_id = event.get("external_id", "compliance-scanner-v1")
    region = event.get("region", "us-east-1")

    if role_arn:
        sts = boto3.client("sts", region_name=region)
        resp = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName="ComplianceScanSession",
            ExternalId=external_id,
        )
        creds = resp["Credentials"]
        return boto3.Session(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
            region_name=region,
        )
    return boto3.Session(region_name=region)


def handler(event: dict, context) -> dict:
    """
    Check that GuardDuty is enabled in the target account and region.

    Expected event:
        {
            "account_id": "123456789012",
            "region": "us-east-1",
            "role_arn": "arn:aws:iam::123456789012:role/ComplianceScannerRole",
            "external_id": "compliance-scanner-v1",
            "trace_context": {...}
        }

    Returns:
        {
            "status": "PASSED" | "FAILED" | "ERROR",
            "message": "...",
            "account_id": "...",
            "region": "...",
            "resource_id": "...",
            "check_id": "guardduty_enabled",
            "remediation": "..."
        }
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"GuardDuty check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        gd_client = session.client("guardduty", region_name=region)

        detectors = gd_client.list_detectors()
        detector_ids = detectors.get("DetectorIds", [])

        if not detector_ids:
            return {
                "status": "FAILED",
                "check_id": "guardduty_enabled",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "GuardDuty has NO detector configured in this account/region.",
                "remediation": (
                    "Enable GuardDuty: "
                    "aws guardduty create-detector --enable "
                    f"--region {region}"
                ),
            }

        # Check if the detector is actually ENABLED
        failed_detectors = []
        for detector_id in detector_ids:
            detail = gd_client.get_detector(DetectorId=detector_id)
            status = detail.get("Status", "DISABLED")
            if status != "ENABLED":
                failed_detectors.append(detector_id)

        if failed_detectors:
            return {
                "status": "FAILED",
                "check_id": "guardduty_enabled",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(failed_detectors),
                "message": (
                    f"GuardDuty detector(s) exist but are DISABLED: {failed_detectors}"
                ),
                "remediation": (
                    "Re-enable each detector: "
                    f"aws guardduty update-detector --detector-id <id> --enable "
                    f"--region {region}"
                ),
            }

        return {
            "status": "PASSED",
            "check_id": "guardduty_enabled",
            "account_id": account_id,
            "region": region,
            "resource_id": ",".join(detector_ids),
            "message": f"GuardDuty is ENABLED. Detectors: {detector_ids}",
            "remediation": None,
        }

    except EndpointResolutionError:
        return {
            "status": "SKIPPED",
            "check_id": "guardduty_enabled",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"GuardDuty not available in region {region}.",
            "remediation": None,
        }
    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError checking GuardDuty: {exc}")
        return {
            "status": "ERROR",
            "check_id": "guardduty_enabled",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": "Check IAM permissions: guardduty:ListDetectors, guardduty:GetDetector",
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in GuardDuty check")
        return {
            "status": "ERROR",
            "check_id": "guardduty_enabled",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
