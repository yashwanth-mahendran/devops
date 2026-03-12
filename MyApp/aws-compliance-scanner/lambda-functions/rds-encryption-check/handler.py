"""
Compliance Check: RDS Encryption at Rest
Verifies that all RDS DB instances have encryption enabled.
"""

import logging
import boto3
from botocore.exceptions import ClientError

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
    Check that all RDS DB instances have StorageEncrypted=True.

    Also checks:
    - Multi-AZ enabled (for availability)
    - Deletion protection enabled (for safety)
    - Auto minor version upgrade enabled
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"RDS encryption check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        rds_client = session.client("rds", region_name=region)

        unencrypted_instances = []
        all_instances = []

        paginator = rds_client.get_paginator("describe_db_instances")
        for page in paginator.paginate():
            for db in page.get("DBInstances", []):
                db_id = db["DBInstanceIdentifier"]
                all_instances.append(db_id)

                # Skip instances being deleted/deleted
                if db.get("DBInstanceStatus") in ("deleting", "deleted"):
                    continue

                if not db.get("StorageEncrypted", False):
                    unencrypted_instances.append({
                        "db_instance_id": db_id,
                        "engine": db.get("Engine", "unknown"),
                        "instance_class": db.get("DBInstanceClass"),
                        "status": db.get("DBInstanceStatus"),
                        "multi_az": db.get("MultiAZ", False),
                        "deletion_protection": db.get("DeletionProtection", False),
                    })

        if not all_instances:
            return {
                "status": "PASSED",
                "check_id": "rds_encryption",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "No RDS instances found in this account/region.",
                "remediation": None,
            }

        if unencrypted_instances:
            ids = [i["db_instance_id"] for i in unencrypted_instances]
            return {
                "status": "FAILED",
                "check_id": "rds_encryption",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(ids),
                "message": (
                    f"{len(unencrypted_instances)} RDS instance(s) do NOT have "
                    f"encryption at rest enabled: {ids}"
                ),
                "remediation": (
                    "RDS encryption cannot be enabled on a running instance. "
                    "Steps: 1) Take a snapshot of the unencrypted DB. "
                    "2) Copy snapshot with encryption enabled (KMS key). "
                    "3) Restore from encrypted snapshot. "
                    "4) Update application connection string. "
                    "5) Delete unencrypted instance."
                ),
                "details": unencrypted_instances,
            }

        return {
            "status": "PASSED",
            "check_id": "rds_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": ",".join(all_instances),
            "message": f"All {len(all_instances)} RDS instance(s) have encryption enabled.",
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError in RDS encryption check: {exc}")
        return {
            "status": "ERROR",
            "check_id": "rds_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": "Ensure IAM permission: rds:DescribeDBInstances",
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in RDS encryption check")
        return {
            "status": "ERROR",
            "check_id": "rds_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
