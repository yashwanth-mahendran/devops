"""
Database layer — supports DynamoDB (primary) and PostgreSQL (RDS fallback).
"""
import boto3
import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# ── DynamoDB ──────────────────────────────────────────────────────────────────

def get_dynamodb():
    return boto3.resource("dynamodb", region_name=settings.AWS_REGION)


def get_scan_table():
    return get_dynamodb().Table(settings.DYNAMODB_SCAN_TABLE)


def get_job_table():
    return get_dynamodb().Table(settings.DYNAMODB_JOB_TABLE)


# ── SQL (RDS / PostgreSQL) ────────────────────────────────────────────────────

_sql_engine = None

def get_sql_engine():
    global _sql_engine
    if _sql_engine is None and settings.DATABASE_URL:
        from sqlalchemy import create_engine
        _sql_engine = create_engine(
            settings.DATABASE_URL,
            pool_pre_ping=True,
            pool_size=5,
            max_overflow=10,
            connect_args={"connect_timeout": 5},
        )
    return _sql_engine


# ── Repository helpers ────────────────────────────────────────────────────────

class ScanRepository:
    """Abstraction over DynamoDB or RDS depending on DB_ENGINE setting."""

    def __init__(self):
        self.engine = settings.DB_ENGINE

    # ── Job CRUD ──────────────────────────────────────────────────────────

    def create_job(self, job: Dict[str, Any]) -> Dict[str, Any]:
        if self.engine == "dynamodb":
            table = get_job_table()
            table.put_item(Item=job)
            return job
        else:
            raise NotImplementedError("SQL backend not implemented for jobs")

    def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        if self.engine == "dynamodb":
            resp = get_job_table().get_item(Key={"job_id": job_id})
            return resp.get("Item")
        raise NotImplementedError

    def update_job(self, job_id: str, updates: Dict[str, Any]) -> None:
        if self.engine == "dynamodb":
            table = get_job_table()
            expressions = []
            values: Dict[str, Any] = {}
            for k, v in updates.items():
                expressions.append(f"{k} = :{k}")
                values[f":{k}"] = v
            table.update_item(
                Key={"job_id": job_id},
                UpdateExpression="SET " + ", ".join(expressions),
                ExpressionAttributeValues=values,
            )
        else:
            raise NotImplementedError

    def list_jobs(self, limit: int = 50) -> List[Dict[str, Any]]:
        if self.engine == "dynamodb":
            resp = get_job_table().scan(Limit=limit)
            return resp.get("Items", [])
        raise NotImplementedError

    # ── Result CRUD ───────────────────────────────────────────────────────

    def save_result(self, result: Dict[str, Any]) -> None:
        if self.engine == "dynamodb":
            get_scan_table().put_item(Item=result)
        else:
            raise NotImplementedError

    def get_results_for_job(self, job_id: str) -> List[Dict[str, Any]]:
        if self.engine == "dynamodb":
            from boto3.dynamodb.conditions import Key as DKey
            resp = get_scan_table().query(
                KeyConditionExpression=DKey("job_id").eq(job_id)
            )
            return resp.get("Items", [])
        raise NotImplementedError
