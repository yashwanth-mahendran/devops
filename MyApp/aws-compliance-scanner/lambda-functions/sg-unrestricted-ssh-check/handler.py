"""
compliance-check-sg-unrestricted-ssh
Detects security groups allowing unrestricted inbound SSH (0.0.0.0/0 on port 22).
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
        ec2 = boto3.client("ec2", region_name=region)
        risky_sgs = []
        paginator = ec2.get_paginator("describe_security_groups")

        for page in paginator.paginate():
            for sg in page["SecurityGroups"]:
                for rule in sg.get("IpPermissions", []):
                    is_ssh   = rule.get("FromPort") == 22
                    is_all   = rule.get("IpProtocol") in ("-1", "tcp")
                    open_v4  = any(r["CidrIp"] == "0.0.0.0/0" for r in rule.get("IpRanges", []))
                    open_v6  = any(r["CidrIpv6"] == "::/0"   for r in rule.get("Ipv6Ranges", []))
                    if is_ssh and is_all and (open_v4 or open_v6):
                        risky_sgs.append(f"{sg['GroupId']} ({sg.get('GroupName', '')})")

        if risky_sgs:
            return _result(
                "FAILED",
                f"{len(risky_sgs)} security group(s) allow unrestricted SSH: {', '.join(risky_sgs[:5])}",
                account_id, region,
                resource_id  = ", ".join(g.split(" ")[0] for g in risky_sgs[:5]),
                remediation  = (
                    "Restrict SSH to specific IP CIDRs: "
                    "aws ec2 revoke-security-group-ingress --group-id <sg-id> "
                    "--protocol tcp --port 22 --cidr 0.0.0.0/0 "
                    "then authorize specific CIDR blocks. "
                    "Use AWS Systems Manager Session Manager instead of direct SSH."
                ),
            )

        return _result("PASSED", "No security groups allow unrestricted SSH", account_id, region)

    except Exception as exc:
        logger.exception("sg_unrestricted_ssh check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
