"""
Database abstraction layer.
Supports DynamoDB (primary) and PostgreSQL (fallback).
"""
import boto3
import logging
from typing import Any, Dict, List, Optional
from botocore.exceptions import ClientError

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


class ScanRepository:
    """Repository pattern for scan jobs and results."""

    def __init__(self):
        self._dynamodb = None
        self._jobs_table = None
        self._results_table = None

    @property
    def dynamodb(self):
        if self._dynamodb is None:
            self._dynamodb = boto3.resource("dynamodb", region_name=settings.AWS_REGION)
        return self._dynamodb

    @property
    def jobs_table(self):
        if self._jobs_table is None:
            self._jobs_table = self.dynamodb.Table(settings.DYNAMODB_JOB_TABLE)
        return self._jobs_table

    @property
    def results_table(self):
        if self._results_table is None:
            self._results_table = self.dynamodb.Table(settings.DYNAMODB_SCAN_TABLE)
        return self._results_table

    # ── Job Operations ───────────────────────────────────────────────────────

    def create_job(self, job: Dict[str, Any]) -> None:
        """Create a new scan job."""
        try:
            self.jobs_table.put_item(Item=job)
            logger.debug("Created job: %s", job["job_id"])
        except ClientError as e:
            logger.exception("Failed to create job: %s", e)
            raise

    def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get a scan job by ID."""
        try:
            response = self.jobs_table.get_item(Key={"job_id": job_id})
            return response.get("Item")
        except ClientError as e:
            logger.exception("Failed to get job %s: %s", job_id, e)
            raise

    def update_job(self, job_id: str, updates: Dict[str, Any]) -> None:
        """Update a scan job."""
        try:
            update_expr = "SET " + ", ".join(f"#{k} = :{k}" for k in updates.keys())
            expr_names = {f"#{k}": k for k in updates.keys()}
            expr_values = {f":{k}": v for k, v in updates.items()}

            self.jobs_table.update_item(
                Key={"job_id": job_id},
                UpdateExpression=update_expr,
                ExpressionAttributeNames=expr_names,
                ExpressionAttributeValues=expr_values,
            )
            logger.debug("Updated job %s: %s", job_id, list(updates.keys()))
        except ClientError as e:
            logger.exception("Failed to update job %s: %s", job_id, e)
            raise

    def list_jobs(self, limit: int = 100) -> List[Dict[str, Any]]:
        """List recent scan jobs."""
        try:
            response = self.jobs_table.scan(Limit=limit)
            jobs = response.get("Items", [])
            # Sort by created_at descending
            jobs.sort(key=lambda x: x.get("created_at", ""), reverse=True)
            return jobs
        except ClientError as e:
            logger.exception("Failed to list jobs: %s", e)
            raise

    # ── Result Operations ────────────────────────────────────────────────────

    def save_result(self, result: Dict[str, Any]) -> None:
        """Save a single check result."""
        try:
            # Composite key: job_id + check_id + account_id + region
            result["pk"] = result["job_id"]
            result["sk"] = f"{result['check_id']}#{result['account_id']}#{result['region']}"
            self.results_table.put_item(Item=result)
        except ClientError as e:
            logger.exception("Failed to save result: %s", e)
            raise

    def save_results_batch(self, results: List[Dict[str, Any]]) -> None:
        """Save multiple results in batch."""
        try:
            with self.results_table.batch_writer() as batch:
                for result in results:
                    result["pk"] = result["job_id"]
                    result["sk"] = f"{result['check_id']}#{result['account_id']}#{result['region']}"
                    batch.put_item(Item=result)
            logger.debug("Saved %d results in batch", len(results))
        except ClientError as e:
            logger.exception("Failed to save results batch: %s", e)
            raise

    def get_results(self, job_id: str) -> List[Dict[str, Any]]:
        """Get all results for a scan job."""
        try:
            response = self.results_table.query(
                KeyConditionExpression="pk = :job_id",
                ExpressionAttributeValues={":job_id": job_id},
            )
            return response.get("Items", [])
        except ClientError as e:
            logger.exception("Failed to get results for job %s: %s", job_id, e)
            raise

    # ── Health Check ─────────────────────────────────────────────────────────

    def health_check(self) -> bool:
        """Check database connectivity."""
        try:
            self.jobs_table.table_status
            return True
        except Exception as e:
            logger.error("Database health check failed: %s", e)
            return False
