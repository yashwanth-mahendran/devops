"""
Application Configuration — Step Functions Approach
Reads from environment variables / AWS Parameter Store at runtime.
"""
from functools import lru_cache
from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    # ── App Identity ──────────────────────────────────────────────────────
    APP_NAME: str = "aws-compliance-scanner-b"
    APP_VERSION: str = "2.0.0"
    ENVIRONMENT: str = "production"
    SLOT: str = "blue"
    LOG_LEVEL: str = "INFO"

    # ── API Security ──────────────────────────────────────────────────────
    API_KEY_HEADER: str = "X-API-Key"
    API_KEYS: List[str] = []

    # ── Database ──────────────────────────────────────────────────────────
    DB_ENGINE: str = "dynamodb"
    DYNAMODB_SCAN_TABLE: str = "compliance-scan-results"
    DYNAMODB_JOB_TABLE: str = "compliance-scan-jobs"
    DATABASE_URL: str = ""

    # ── AWS Settings ──────────────────────────────────────────────────────
    AWS_REGION: str = "us-east-1"
    
    # Step Functions ARN — the core change from Approach A
    STEP_FUNCTION_ARN: str = ""
    
    # Lambda settings (for reference, now managed by Step Functions)
    LAMBDA_FUNCTION_PREFIX: str = "compliance-check"
    ASSUME_ROLE_ARN_TEMPLATE: str = "arn:aws:iam::{account_id}:role/ComplianceScannerRole"

    # ── Observability ─────────────────────────────────────────────────────
    OTEL_EXPORTER_OTLP_ENDPOINT: str = "http://otel-collector.monitoring:4317"
    ENABLE_TRACING: bool = True

    # ── Step Functions Settings ───────────────────────────────────────────
    # With Step Functions, these are now configured in the state machine
    # Keeping for reference / fallback to direct Lambda mode
    MAX_CONCURRENT_LAMBDA_CALLS: int = 20  # Now handled by Map state MaxConcurrency
    SCAN_TIMEOUT_SECONDS: int = 300        # Now handled by Step Functions timeout

    # ── Execution Mode ────────────────────────────────────────────────────
    # sync:  Use startSyncExecution (Express Workflow) — blocks until complete
    # async: Use startExecution — returns immediately, poll for results
    EXECUTION_MODE: str = "async"

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()
