"""
Application Configuration
Reads from environment variables / AWS Parameter Store at runtime.
"""
from functools import lru_cache
from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    # ── App Identity ──────────────────────────────────────────────────────
    APP_NAME: str = "aws-compliance-scanner"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "production"          # production | staging | dev
    SLOT: str = "blue"                       # blue | green  (for blue/green)
    LOG_LEVEL: str = "INFO"

    # ── API Security ──────────────────────────────────────────────────────
    API_KEY_HEADER: str = "X-API-Key"
    API_KEYS: List[str] = []                 # Injected via k8s secret

    # ── Database ──────────────────────────────────────────────────────────
    DB_ENGINE: str = "dynamodb"              # dynamodb | postgres
    DYNAMODB_SCAN_TABLE: str = "compliance-scan-results"
    DYNAMODB_JOB_TABLE: str  = "compliance-scan-jobs"
    # Postgres (RDS) fallback
    DATABASE_URL: str = ""

    # ── AWS Settings ──────────────────────────────────────────────────────
    AWS_REGION: str = "us-east-1"
    LAMBDA_FUNCTION_PREFIX: str = "compliance-check"
    ASSUME_ROLE_ARN_TEMPLATE: str = "arn:aws:iam::{account_id}:role/ComplianceScannerRole"

    # ── Observability ─────────────────────────────────────────────────────
    OTEL_EXPORTER_OTLP_ENDPOINT: str = "http://otel-collector.monitoring:4317"
    ENABLE_TRACING: bool = True

    # ── Feature flags ─────────────────────────────────────────────────────
    MAX_CONCURRENT_LAMBDA_CALLS: int = 20
    SCAN_TIMEOUT_SECONDS: int = 300

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()
