"""
compliance-check-cfn-drift
Checks if any CloudFormation stacks have drifted from their expected configuration.
"""
import boto3
import json
import logging
import time
from typing import Any, Dict

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    account_id = event["account_id"]
    region     = event["region"]
    job_id     = event["job_id"]

    logger.info("cfn_drift check | job=%s account=%s region=%s", job_id, account_id, region)

    try:
        cfn = boto3.client("cloudformation", region_name=region)

        # List all stacks (excluding deleted)
        stacks = []
        paginator = cfn.get_paginator("list_stacks")
        for page in paginator.paginate(
            StackStatusFilter=[
                "CREATE_COMPLETE", "UPDATE_COMPLETE", "ROLLBACK_COMPLETE",
                "UPDATE_ROLLBACK_COMPLETE",
            ]
        ):
            stacks.extend(page["StackSummaries"])

        if not stacks:
            return _result("PASSED", "No CloudFormation stacks found", account_id, region)

        drifted_stacks = []
        for stack in stacks:
            stack_name = stack["StackName"]
            try:
                # Initiate drift detection
                detect_resp = cfn.detect_stack_drift(StackName=stack_name)
                detection_id = detect_resp["StackDriftDetectionId"]

                # Poll until complete (with timeout)
                deadline = time.time() + 60
                while time.time() < deadline:
                    status_resp = cfn.describe_stack_drift_detection_status(
                        StackDriftDetectionId=detection_id
                    )
                    detection_status = status_resp["DetectionStatus"]
                    if detection_status in ("DETECTION_COMPLETE", "DETECTION_FAILED"):
                        break
                    time.sleep(3)

                drift_status = status_resp.get("StackDriftStatus", "UNKNOWN")
                if drift_status == "DRIFTED":
                    drifted_stacks.append(stack_name)

            except cfn.exceptions.ClientError as e:
                logger.warning("Could not check drift for %s: %s", stack_name, e)

        if drifted_stacks:
            return _result(
                "FAILED",
                f"{len(drifted_stacks)} of {len(stacks)} stacks have drifted: {', '.join(drifted_stacks[:5])}",
                account_id,
                region,
                resource_id   = ", ".join(drifted_stacks[:5]),
                remediation   = (
                    "Run 'aws cloudformation detect-stack-drift' to identify drifted resources. "
                    "Use 'aws cloudformation update-stack' or manual remediation to realign stacks. "
                    "Enable AWS Config rule 'cloudformation-stack-drift-detection-check'."
                ),
            )

        return _result(
            "PASSED",
            f"All {len(stacks)} CloudFormation stacks are in sync",
            account_id, region,
        )

    except Exception as exc:
        logger.exception("cfn_drift check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {
        "status":      status,
        "message":     message,
        "account_id":  account_id,
        "region":      region,
        "resource_id": resource_id,
        "remediation": remediation,
    }
