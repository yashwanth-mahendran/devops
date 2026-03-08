"""
Compliance Check: Secrets Manager Rotation
Verifies that secrets stored in AWS Secrets Manager have automatic rotation enabled.
"""

import logging
import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_boto3_session(event: dict) -> boto3.Session:
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
    Check that all Secrets Manager secrets have:
    1. RotationEnabled = True
    2. Last rotated within the rotation schedule (not overdue)

    Excludes secrets tagged with `compliance-scanner-skip: true`.
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")
    overdue_threshold_days = event.get("overdue_threshold_days", 30)

    logger.info(f"Secrets Manager rotation check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        sm_client = session.client("secretsmanager", region_name=region)

        no_rotation = []
        overdue_rotation = []
        total_secrets = 0

        paginator = sm_client.get_paginator("list_secrets")
        for page in paginator.paginate():
            for secret in page.get("SecretList", []):
                secret_name = secret.get("Name", "unknown")
                total_secrets += 1

                # Skip explicitly tagged as ignored
                tags = {t["Key"]: t["Value"] for t in secret.get("Tags", [])}
                if tags.get("compliance-scanner-skip", "").lower() == "true":
                    continue

                rotation_enabled = secret.get("RotationEnabled", False)

                if not rotation_enabled:
                    no_rotation.append(secret_name)
                    continue

                # Check if rotation is overdue
                last_rotated = secret.get("LastRotatedDate")
                rotation_rules = secret.get("RotationRules", {})
                rotation_days = rotation_rules.get("AutomaticallyAfterDays", overdue_threshold_days)

                if last_rotated:
                    days_since = (datetime.now(timezone.utc) - last_rotated).days
                    if days_since > rotation_days + overdue_threshold_days:
                        overdue_rotation.append({
                            "secret": secret_name,
                            "days_since_rotation": days_since,
                            "rotation_schedule_days": rotation_days,
                        })

        if not total_secrets:
            return {
                "status": "PASSED",
                "check_id": "secrets_manager_rotation",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "No Secrets Manager secrets found in this account/region.",
                "remediation": None,
            }

        issues = []
        resource_ids = []

        if no_rotation:
            issues.append(f"{len(no_rotation)} secret(s) have NO rotation: {no_rotation[:5]}")
            resource_ids.extend(no_rotation[:5])

        if overdue_rotation:
            overdue_names = [o["secret"] for o in overdue_rotation]
            issues.append(
                f"{len(overdue_rotation)} secret(s) have overdue rotation: {overdue_names[:5]}"
            )
            resource_ids.extend(overdue_names[:5])

        if issues:
            return {
                "status": "FAILED",
                "check_id": "secrets_manager_rotation",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(resource_ids) or f"account/{account_id}",
                "message": " | ".join(issues),
                "remediation": (
                    "Enable rotation for each secret: "
                    "aws secretsmanager rotate-secret --secret-id <name> "
                    "--rotation-lambda-arn <arn> "
                    "--rotation-rules AutomaticallyAfterDays=30. "
                    "Use AWS-provided rotation Lambdas for RDS/Redshift/DocumentDB."
                ),
                "details": {
                    "no_rotation": no_rotation[:20],
                    "overdue_rotation": overdue_rotation[:10],
                },
            }

        return {
            "status": "PASSED",
            "check_id": "secrets_manager_rotation",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": (
                f"All {total_secrets} secret(s) have rotation enabled and are "
                "within their rotation schedule."
            ),
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError in Secrets Manager rotation check: {exc}")
        return {
            "status": "ERROR",
            "check_id": "secrets_manager_rotation",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": "Ensure IAM permission: secretsmanager:ListSecrets",
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in Secrets Manager rotation check")
        return {
            "status": "ERROR",
            "check_id": "secrets_manager_rotation",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
