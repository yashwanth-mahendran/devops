"""
Pydantic schemas for request/response models.
"""
from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field


class CheckStatus(str, Enum):
    PASSED = "PASSED"
    FAILED = "FAILED"
    ERROR = "ERROR"


class JobStatus(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    PARTIAL = "PARTIAL"
    FAILED = "FAILED"


# ── Request Models ───────────────────────────────────────────────────────────

class ScanRequest(BaseModel):
    """Request to submit a new compliance scan."""
    account_ids: List[str] = Field(..., min_length=1, description="AWS account IDs to scan")
    regions: List[str] = Field(..., min_length=1, description="AWS regions to scan")
    checks: Optional[List[str]] = Field(None, description="Specific checks to run (defaults to all)")

    model_config = {
        "json_schema_extra": {
            "examples": [{
                "account_ids": ["123456789012", "987654321098"],
                "regions": ["us-east-1", "eu-west-1"],
                "checks": ["cfn_drift", "vpc_flow_logs", "s3_encryption"]
            }]
        }
    }


class RescanRequest(BaseModel):
    """Request to rescan specific checks from a previous scan."""
    checks: Optional[List[str]] = Field(None, description="Specific checks to re-run")
    only_failed: bool = Field(False, description="Re-run only failed checks from original scan")


# ── Response Models ──────────────────────────────────────────────────────────

class CheckResult(BaseModel):
    """Result of a single compliance check."""
    check_id: str
    check_name: str
    account_id: str
    region: str
    status: CheckStatus
    resource_id: Optional[str] = None
    message: str
    remediation: Optional[str] = None
    severity: str
    timestamp: str


class ScanJobResponse(BaseModel):
    """Full scan job response with results."""
    job_id: str
    status: JobStatus
    account_ids: List[str]
    regions: List[str]
    checks: List[str]
    created_at: str
    completed_at: Optional[str] = None
    total_checks: int = 0
    passed: int = 0
    failed: int = 0
    errors: int = 0
    execution_arn: Optional[str] = None  # Step Functions execution ARN
    parent_job_id: Optional[str] = None  # For rescan jobs
    results: Optional[List[CheckResult]] = None


class ScanSummaryResponse(BaseModel):
    """Summary of a scan job (for listing)."""
    job_id: str
    status: JobStatus
    total_checks: int
    passed: int
    failed: int
    errors: int
    pass_rate: float
    created_at: str
    completed_at: Optional[str] = None
    execution_arn: Optional[str] = None


class ExecutionStatusResponse(BaseModel):
    """Step Functions execution status."""
    job_id: str
    execution_arn: str
    status: str  # RUNNING, SUCCEEDED, FAILED, TIMED_OUT, ABORTED
    start_date: Optional[str] = None
    stop_date: Optional[str] = None
    error: Optional[str] = None
    cause: Optional[str] = None


# ── Health Check Models ──────────────────────────────────────────────────────

class HealthResponse(BaseModel):
    status: str
    version: str
    slot: str
    environment: str


class ReadinessResponse(BaseModel):
    status: str
    checks: dict
