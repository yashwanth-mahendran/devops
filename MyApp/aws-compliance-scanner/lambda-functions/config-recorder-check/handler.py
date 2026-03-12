"""
Compliance Check: AWS Config Recorder Enabled
Verifies that an AWS Config configuration recorder is set up and actively recording.
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
    Verifies that AWS Config is enabled and recording.

    Checks:
    1. At least one configuration recorder exists.
    2. The recorder is in RECORDING state.
    3. Delivery channel exists (Config needs a delivery channel to be useful).
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"Config recorder check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        config_client = session.client("config", region_name=region)

        # Check configuration recorders
        recorders_resp = config_client.describe_configuration_recorders()
        recorders = recorders_resp.get("ConfigurationRecorders", [])

        if not recorders:
            return {
                "status": "FAILED",
                "check_id": "config_recorder",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "No AWS Config configuration recorder found in this account/region.",
                "remediation": (
                    "Enable AWS Config: "
                    "aws configservice put-configuration-recorder "
                    "--configuration-recorder name=default,roleARN=<ConfigRole> "
                    "--recording-group allSupported=true,includeGlobalResourceTypes=true"
                ),
            }

        # Check recorder status
        recorder_names = [r["name"] for r in recorders]
        status_resp = config_client.describe_configuration_recorder_status(
            ConfigurationRecorderNames=recorder_names
        )
        statuses = status_resp.get("ConfigurationRecordersStatus", [])

        not_recording = [
            s["name"] for s in statuses if not s.get("recording", False)
        ]

        if not_recording:
            return {
                "status": "FAILED",
                "check_id": "config_recorder",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(not_recording),
                "message": f"Config recorder(s) exist but are NOT recording: {not_recording}",
                "remediation": (
                    "Start the recorder: "
                    "aws configservice start-configuration-recorder "
                    f"--configuration-recorder-name {not_recording[0]}"
                ),
            }

        # Verify delivery channel exists
        channels_resp = config_client.describe_delivery_channels()
        channels = channels_resp.get("DeliveryChannels", [])

        if not channels:
            return {
                "status": "FAILED",
                "check_id": "config_recorder",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "Config recorder is running but no delivery channel configured.",
                "remediation": (
                    "aws configservice put-delivery-channel "
                    "--delivery-channel name=default,s3BucketName=<config-bucket>"
                ),
            }

        return {
            "status": "PASSED",
            "check_id": "config_recorder",
            "account_id": account_id,
            "region": region,
            "resource_id": ",".join(recorder_names),
            "message": (
                f"AWS Config recorder(s) active: {recorder_names}. "
                f"Delivery channel(s): {[c['name'] for c in channels]}"
            ),
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError checking Config recorder: {exc}")
        return {
            "status": "ERROR",
            "check_id": "config_recorder",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": (
                "Check IAM permissions: "
                "config:DescribeConfigurationRecorders, "
                "config:DescribeConfigurationRecorderStatus, "
                "config:DescribeDeliveryChannels"
            ),
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in Config recorder check")
        return {
            "status": "ERROR",
            "check_id": "config_recorder",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
