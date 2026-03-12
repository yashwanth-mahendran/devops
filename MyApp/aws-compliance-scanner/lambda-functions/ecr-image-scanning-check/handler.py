"""
Compliance Check: ECR Image Scanning on Push
Verifies that all ECR repositories have scan-on-push enabled.
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
    Check that all ECR repositories have:
    1. imageScanningConfiguration.scanOnPush = True
    2. (Optional) imageTagMutability = IMMUTABLE (best practice)
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"ECR image scanning check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        ecr_client = session.client("ecr", region_name=region)

        repos_without_scanning = []
        repos_with_mutable_tags = []
        total_repos = 0

        paginator = ecr_client.get_paginator("describe_repositories")
        for page in paginator.paginate():
            for repo in page.get("repositories", []):
                total_repos += 1
                repo_name = repo["repositoryName"]

                scan_config = repo.get("imageScanningConfiguration", {})
                scan_on_push = scan_config.get("scanOnPush", False)

                if not scan_on_push:
                    repos_without_scanning.append(repo_name)

                tag_mutability = repo.get("imageTagMutability", "MUTABLE")
                if tag_mutability == "MUTABLE":
                    repos_with_mutable_tags.append(repo_name)

        if not total_repos:
            return {
                "status": "PASSED",
                "check_id": "ecr_image_scanning",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "No ECR repositories found in this account/region.",
                "remediation": None,
            }

        if repos_without_scanning:
            return {
                "status": "FAILED",
                "check_id": "ecr_image_scanning",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(repos_without_scanning[:10]),
                "message": (
                    f"{len(repos_without_scanning)} ECR repo(s) do NOT have "
                    f"scan-on-push enabled: {repos_without_scanning[:5]}"
                ),
                "remediation": (
                    "Enable scan-on-push for each repo: "
                    "aws ecr put-image-scanning-configuration "
                    "--repository-name <name> "
                    "--image-scanning-configuration scanOnPush=true "
                    f"--region {region}. "
                    "Consider also enabling IMMUTABLE tags: "
                    "aws ecr put-image-tag-mutability "
                    "--repository-name <name> --image-tag-mutability IMMUTABLE"
                ),
                "details": {
                    "repos_without_scanning": repos_without_scanning[:20],
                    "repos_with_mutable_tags": repos_with_mutable_tags[:20],
                },
            }

        # Passed scanning check — warn on mutable tags as advisory
        message = (
            f"All {total_repos} ECR repo(s) have scan-on-push enabled."
        )
        if repos_with_mutable_tags:
            message += (
                f" Advisory: {len(repos_with_mutable_tags)} repo(s) have MUTABLE tags "
                "(recommend IMMUTABLE for supply-chain security)."
            )

        return {
            "status": "PASSED",
            "check_id": "ecr_image_scanning",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": message,
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError in ECR scanning check: {exc}")
        return {
            "status": "ERROR",
            "check_id": "ecr_image_scanning",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": "Ensure IAM permission: ecr:DescribeRepositories",
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in ECR scanning check")
        return {
            "status": "ERROR",
            "check_id": "ecr_image_scanning",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
