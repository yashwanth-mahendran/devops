"""
Compliance Check: EBS Volume Encryption
Verifies that all EBS volumes have encryption enabled.
Also checks that the account-level EBS encryption by default setting is enabled.
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
    Check that:
    1. EBS encryption by default is ENABLED for the account in the region.
    2. All existing EBS volumes are encrypted.

    Returns FAILED if either condition is not met.
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"EBS encryption check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        ec2_client = session.client("ec2", region_name=region)

        # 1. Check account-level EBS encryption by default
        default_enc_resp = ec2_client.get_ebs_encryption_by_default()
        encryption_by_default = default_enc_resp.get("EbsEncryptionByDefault", False)

        # 2. Check existing volumes
        unencrypted_volumes = []
        paginator = ec2_client.get_paginator("describe_volumes")
        for page in paginator.paginate():
            for volume in page.get("Volumes", []):
                if not volume.get("Encrypted", False):
                    instance_ids = [
                        a["InstanceId"]
                        for a in volume.get("Attachments", [])
                    ]
                    unencrypted_volumes.append({
                        "volume_id": volume["VolumeId"],
                        "volume_type": volume.get("VolumeType"),
                        "size_gib": volume.get("Size"),
                        "state": volume.get("State"),
                        "attached_to": instance_ids,
                    })

        issues = []
        if not encryption_by_default:
            issues.append(
                f"EBS encryption by default is DISABLED for account {account_id} in {region}."
            )

        if unencrypted_volumes:
            vol_ids = [v["volume_id"] for v in unencrypted_volumes]
            issues.append(
                f"{len(unencrypted_volumes)} unencrypted EBS volume(s): {vol_ids}"
            )

        if issues:
            vol_ids_str = (
                ",".join(v["volume_id"] for v in unencrypted_volumes)
                if unencrypted_volumes
                else f"account/{account_id}"
            )
            return {
                "status": "FAILED",
                "check_id": "ebs_encryption",
                "account_id": account_id,
                "region": region,
                "resource_id": vol_ids_str,
                "message": " | ".join(issues),
                "remediation": (
                    "1. Enable EBS encryption by default: "
                    f"aws ec2 enable-ebs-encryption-by-default --region {region}. "
                    "2. For existing unencrypted volumes: create snapshot → "
                    "copy snapshot with --encrypted flag → create new volume → migrate data."
                ),
                "details": unencrypted_volumes[:20],  # cap at 20 in response
            }

        return {
            "status": "PASSED",
            "check_id": "ebs_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": (
                "EBS encryption by default is ENABLED and "
                "all existing volumes are encrypted."
            ),
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError in EBS encryption check: {exc}")
        return {
            "status": "ERROR",
            "check_id": "ebs_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": (
                "Ensure IAM permissions: "
                "ec2:GetEbsEncryptionByDefault, ec2:DescribeVolumes"
            ),
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in EBS encryption check")
        return {
            "status": "ERROR",
            "check_id": "ebs_encryption",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
