"""
compliance-check-iam-mfa-root
Verifies that the root account has MFA enabled and that all IAM users with console access have MFA.
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
        iam = boto3.client("iam", region_name="us-east-1")  # IAM is global

        # ── Root MFA check ──────────────────────────────────────────────────
        account_summary = iam.get_account_summary()["SummaryMap"]
        root_mfa_active = account_summary.get("AccountMFAEnabled", 0)

        if not root_mfa_active:
            return _result(
                "FAILED",
                "Root account MFA is NOT enabled — CRITICAL security risk",
                account_id, region,
                remediation = (
                    "Enable MFA on the root account immediately: "
                    "Sign in as root → AWS Console → My Security Credentials → "
                    "Multi-factor authentication (MFA) → Activate MFA."
                ),
            )

        # ── IAM users without MFA ───────────────────────────────────────────
        users_without_mfa = []
        paginator = iam.get_paginator("list_users")
        for page in paginator.paginate():
            for user in page["Users"]:
                username = user["UserName"]
                # Only check users with console access (login profile)
                try:
                    iam.get_login_profile(UserName=username)
                except iam.exceptions.NoSuchEntityException:
                    continue  # no console access → skip
                mfa_devices = iam.list_mfa_devices(UserName=username)["MFADevices"]
                if not mfa_devices:
                    users_without_mfa.append(username)

        if users_without_mfa:
            return _result(
                "FAILED",
                f"Root MFA OK but {len(users_without_mfa)} IAM user(s) lack MFA: {', '.join(users_without_mfa[:5])}",
                account_id, region,
                resource_id  = ", ".join(users_without_mfa[:5]),
                remediation  = (
                    "Enforce MFA for IAM users by attaching an IAM policy that denies "
                    "all actions unless MFA is present, and attach a virtual/hardware MFA device. "
                    "Consider moving to IAM Identity Center (SSO) for centralized MFA management."
                ),
            )

        return _result("PASSED", "Root MFA enabled and all console IAM users have MFA", account_id, region)

    except Exception as exc:
        logger.exception("iam_mfa check error: %s", exc)
        return _result("ERROR", str(exc), account_id, region)


def _result(status, message, account_id, region, resource_id=None, remediation=None):
    return {"status": status, "message": message, "account_id": account_id,
            "region": region, "resource_id": resource_id, "remediation": remediation}
