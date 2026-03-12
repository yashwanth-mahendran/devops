"""
compliance-check-s3-encryption
Verifies default encryption is enabled on all S3 buckets.
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
        s3 = boto3.client("s3", region_name=region)
        buckets = s3.list_buckets().get("Buckets", [])

        if not buckets:
            return _result("PASSED", "No S3 buckets found", account_id, region)

        unencrypted = []
        for bucket in buckets:
            name = bucket["Name"]
            try:
                s3.get_bucket_encryption(Bucket=name)
            except s3.exceptions.ClientError as e:
                if e.response["Error"]["Code"] == "ServerSideEncryptionConfigurationNotFoundError":
                    unencrypted.append(name)

        if unencrypted:
            return _result(
                "FAILED",
                f"{len(unencrypted)} bucket(s) missing default encryption: {', '.join(unencrypted[:5])}",
                account_id, region,
                resource_id  = ", ".join(unencrypted[:5]),
                remediation  = (
                    "Enable S3 default encryption: "
                    "aws s3api put-bucket-encryption --bucket <name> "
                    "--server-side-encryption-configuration "
                    "'{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\"}}]}'"
                ),
            )

        return _result("PASSED", f"All {len(buckets)} S3 bucket(s) have default encryption", account_id, region)

    except Exception as exc:
        logger.exception("s3_encryption check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
