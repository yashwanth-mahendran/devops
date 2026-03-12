"""
Health check endpoints.
"""
from fastapi import APIRouter
from app.config import get_settings
from app.database import ScanRepository
from app.schemas import HealthResponse, ReadinessResponse

settings = get_settings()
router = APIRouter(tags=["health"])
repo = ScanRepository()


@router.get("/healthz", response_model=HealthResponse)
async def health():
    """Liveness probe — is the application running?"""
    return HealthResponse(
        status="healthy",
        version=settings.APP_VERSION,
        slot=settings.SLOT,
        environment=settings.ENVIRONMENT,
    )


@router.get("/readyz", response_model=ReadinessResponse)
async def readiness():
    """Readiness probe — is the application ready to serve traffic?"""
    checks = {
        "database": repo.health_check(),
    }
    
    all_healthy = all(checks.values())
    return ReadinessResponse(
        status="ready" if all_healthy else "not_ready",
        checks=checks,
    )


@router.get("/metrics/summary")
async def metrics_summary():
    """Custom metrics summary for debugging."""
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "slot": settings.SLOT,
        "step_function_arn": settings.STEP_FUNCTION_ARN,
    }
