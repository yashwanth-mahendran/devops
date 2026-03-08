"""
Compliance Check: EKS Control Plane Logging
Verifies that all EKS clusters have control plane logging enabled for critical log types.
"""

import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Required logging types as per CIS EKS Benchmark
REQUIRED_LOG_TYPES = {"api", "audit", "authenticator"}
RECOMMENDED_LOG_TYPES = {"controllerManager", "scheduler"}


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
    Check that all EKS clusters have control plane logging enabled for:
    - api (required)
    - audit (required)
    - authenticator (required)
    - controllerManager (recommended)
    - scheduler (recommended)
    """
    account_id = event.get("account_id", "unknown")
    region = event.get("region", "us-east-1")

    logger.info(f"EKS cluster logging check | account={account_id} region={region}")

    try:
        session = get_boto3_session(event)
        eks_client = session.client("eks", region_name=region)

        clusters_with_missing_logs = []
        total_clusters = 0

        # List all EKS clusters in the region
        paginator = eks_client.get_paginator("list_clusters")
        cluster_names = []
        for page in paginator.paginate():
            cluster_names.extend(page.get("clusters", []))

        for cluster_name in cluster_names:
            total_clusters += 1
            cluster_detail = eks_client.describe_cluster(name=cluster_name)
            cluster = cluster_detail.get("cluster", {})

            logging_config = cluster.get("logging", {})
            cluster_logging = logging_config.get("clusterLogging", [])

            # Extract enabled log types
            enabled_types = set()
            for log_group in cluster_logging:
                if log_group.get("enabled", False):
                    enabled_types.update(log_group.get("types", []))

            missing_required = REQUIRED_LOG_TYPES - enabled_types
            missing_recommended = RECOMMENDED_LOG_TYPES - enabled_types

            if missing_required:
                clusters_with_missing_logs.append({
                    "cluster_name": cluster_name,
                    "enabled_log_types": list(enabled_types),
                    "missing_required": list(missing_required),
                    "missing_recommended": list(missing_recommended),
                    "kubernetes_version": cluster.get("version", "unknown"),
                    "status": cluster.get("status", "unknown"),
                })

        if not total_clusters:
            return {
                "status": "PASSED",
                "check_id": "eks_cluster_logging",
                "account_id": account_id,
                "region": region,
                "resource_id": f"account/{account_id}",
                "message": "No EKS clusters found in this account/region.",
                "remediation": None,
            }

        if clusters_with_missing_logs:
            cluster_names_failing = [c["cluster_name"] for c in clusters_with_missing_logs]
            return {
                "status": "FAILED",
                "check_id": "eks_cluster_logging",
                "account_id": account_id,
                "region": region,
                "resource_id": ",".join(cluster_names_failing),
                "message": (
                    f"{len(clusters_with_missing_logs)} EKS cluster(s) are missing required "
                    f"control plane log types: {cluster_names_failing}"
                ),
                "remediation": (
                    "Enable all log types for each cluster: "
                    "aws eks update-cluster-config "
                    "--name <cluster-name> "
                    '--logging \'{"clusterLogging":[{"types":["api","audit",'
                    '"authenticator","controllerManager","scheduler"],"enabled":true}]}\' '
                    f"--region {region}"
                ),
                "details": clusters_with_missing_logs,
            }

        return {
            "status": "PASSED",
            "check_id": "eks_cluster_logging",
            "account_id": account_id,
            "region": region,
            "resource_id": ",".join(cluster_names),
            "message": (
                f"All {total_clusters} EKS cluster(s) have the required control "
                f"plane log types enabled: {REQUIRED_LOG_TYPES}"
            ),
            "remediation": None,
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(f"ClientError in EKS cluster logging check: {exc}")
        return {
            "status": "ERROR",
            "check_id": "eks_cluster_logging",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": f"AWS error: {error_code} — {exc}",
            "remediation": (
                "Ensure IAM permissions: eks:ListClusters, eks:DescribeCluster"
            ),
        }
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("Unexpected error in EKS cluster logging check")
        return {
            "status": "ERROR",
            "check_id": "eks_cluster_logging",
            "account_id": account_id,
            "region": region,
            "resource_id": f"account/{account_id}",
            "message": str(exc),
            "remediation": None,
        }
