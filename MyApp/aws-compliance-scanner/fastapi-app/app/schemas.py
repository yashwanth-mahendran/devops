"""
Pydantic schemas (request / response models).
"""
from enum import Enum
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field
from datetime import datetime


class CheckStatus(str, Enum):
    PASSED  = "PASSED"
    FAILED  = "FAILED"
    ERROR   = "ERROR"
    SKIPPED = "SKIPPED"


class JobStatus(str, Enum):
    PENDING    = "PENDING"
    RUNNING    = "RUNNING"
    COMPLETED  = "COMPLETED"
    FAILED     = "FAILED"
    PARTIAL    = "PARTIAL"


# ── Inbound Requests ──────────────────────────────────────────────────────────

class ScanRequest(BaseModel):
    account_ids: List[str]              = Field(..., description="AWS account IDs to scan")
    regions:     List[str]              = Field(default=["us-east-1"])
    checks:      Optional[List[str]]    = Field(default=None, description="Specific checks to run. Omit for all.")
    tags:        Optional[Dict[str, str]] = Field(default=None, description="Filter resources by tag key/value")

    class Config:
        json_schema_extra = {
            "example": {
                "account_ids": ["123456789012", "987654321098"],
                "regions": ["us-east-1", "eu-west-1"],
                "checks": ["cfn_drift", "vpc_flow_logs", "audit_manager"],
            }
        }

class RescanRequest(BaseModel):
    checks: Optional[List[str]] = None


# ── Outbound Responses ────────────────────────────────────────────────────────

class CheckResult(BaseModel):
    check_id:    str
    check_name:  str
    account_id:  str
    region:      str
    status:      CheckStatus
    resource_id: Optional[str]   = None
    message:     str
    remediation: Optional[str]   = None
    severity:    str             = "MEDIUM"     # LOW | MEDIUM | HIGH | CRITICAL
    timestamp:   str


class ScanJobResponse(BaseModel):
    job_id:      str
    status:      JobStatus
    account_ids: List[str]
    regions:     List[str]
    checks:      List[str]
    created_at:  str
    completed_at: Optional[str] = None
    total_checks: int = 0
    passed:       int = 0
    failed:       int = 0
    errors:       int = 0
    results:      Optional[List[CheckResult]] = None


class ScanSummaryResponse(BaseModel):
    job_id:       str
    status:       JobStatus
    total_checks: int
    passed:       int
    failed:       int
    errors:       int
    pass_rate:    float
    created_at:   str
    completed_at: Optional[str] = None


class HealthResponse(BaseModel):
    status:      str
    version:     str
    environment: str
    slot:        str             # blue | green
    timestamp:   str


class ErrorResponse(BaseModel):
    error:   str
    detail:  Optional[str] = None
    code:    Optional[str] = None
