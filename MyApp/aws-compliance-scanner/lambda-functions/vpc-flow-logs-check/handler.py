"""
compliance-check-vpc-flow-logs
Verifies that VPC Flow Logs are enabled for all VPCs in the account/region.
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

    logger.info("vpc_flow_logs check | job=%s account=%s region=%s", job_id, account_id, region)

    try:
        ec2 = boto3.client("ec2", region_name=region)

        # List all VPCs
        vpcs = ec2.describe_vpcs()["Vpcs"]
        if not vpcs:
            return _result("PASSED", "No VPCs found", account_id, region)

        vpc_ids = [v["VpcId"] for v in vpcs]

        # Get flow logs
        flow_logs = ec2.describe_flow_logs(
            Filters=[{"Name": "resource-id", "Values": vpc_ids}]
        )["FlowLogs"]

        vpcs_with_logs = {fl["ResourceId"] for fl in flow_logs if fl.get("FlowLogStatus") == "ACTIVE"}
        vpcs_without   = [v for v in vpc_ids if v not in vpcs_with_logs]

        if vpcs_without:
            return _result(
                "FAILED",
                f"{len(vpcs_without)} VPC(s) missing active flow logs: {', '.join(vpcs_without[:5])}",
                account_id,
                region,
                resource_id  = ", ".join(vpcs_without[:5]),
                remediation  = (
                    "Enable VPC Flow Logs: "
                    "aws ec2 create-flow-logs "
                    "--resource-type VPC --resource-ids <vpc-id> "
                    "--traffic-type ALL --log-destination-type cloud-watch-logs "
                    "--log-group-name /vpc/flow-logs "
                    "--deliver-logs-permission-arn <iam-role-arn>"
                ),
            )

        return _result(
            "PASSED",
            f"All {len(vpc_ids)} VPC(s) have active flow logs",
            account_id, region,
        )

    except Exception as exc:
        logger.exception("vpc_flow_logs check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
