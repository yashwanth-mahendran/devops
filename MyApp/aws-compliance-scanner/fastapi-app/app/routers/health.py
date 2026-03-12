"""Health & readiness probes."""
from datetime import datetime, timezone
from fastapi import APIRouter
from app.config import get_settings
from app.schemas import HealthResponse

settings = get_settings()
router   = APIRouter(tags=["health"])


@router.get("/healthz", response_model=HealthResponse)
async def liveness():
    return HealthResponse(
        status      = "ok",
        version     = settings.APP_VERSION,
        environment = settings.ENVIRONMENT,
        slot        = settings.SLOT,
        timestamp   = datetime.now(timezone.utc).isoformat(),
    )


@router.get("/readyz", response_model=HealthResponse)
async def readiness():
    """
    Readiness includes a lightweight DynamoDB ping.
    Kubernetes will stop routing traffic if this returns non-200.
    """
    try:
        from app.database import get_job_table
        get_job_table().load()          # raises if table doesn't exist / no perms
    except Exception as exc:
        from fastapi import HTTPException
        raise HTTPException(status_code=503, detail=f"DynamoDB not ready: {exc}")

    return HealthResponse(
        status      = "ready",
        version     = settings.APP_VERSION,
        environment = settings.ENVIRONMENT,
        slot        = settings.SLOT,
        timestamp   = datetime.now(timezone.utc).isoformat(),
    )


@router.get("/metrics/summary")
async def metrics_summary():
    """Simple Prometheus-style summary (replace with /metrics for full exposition)."""
    from app.database import ScanRepository
    from app.schemas import JobStatus
    repo = ScanRepository()
    jobs = repo.list_jobs(limit=200)
    total   = len(jobs)
    running = sum(1 for j in jobs if j["status"] == JobStatus.RUNNING.value)
    failed  = sum(1 for j in jobs if j["status"] == JobStatus.FAILED.value)
    return {"total_jobs": total, "running": running, "failed": failed}
