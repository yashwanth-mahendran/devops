"""
/scan routes — submit and manage compliance scan jobs.
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Security, BackgroundTasks
from fastapi.security.api_key import APIKeyHeader

from app.config import get_settings
from app.database import ScanRepository
from app.schemas import (
    CheckStatus, JobStatus,
    ScanRequest, ScanJobResponse, ScanSummaryResponse,
    RescanRequest,
)
from app.services.lambda_invoker import run_checks_async, REGISTERED_CHECKS

logger   = logging.getLogger(__name__)
settings = get_settings()

router       = APIRouter(prefix="/scan", tags=["scan"])
api_key_hdr  = APIKeyHeader(name=settings.API_KEY_HEADER, auto_error=True)
repo         = ScanRepository()


def verify_api_key(api_key: str = Security(api_key_hdr)):
    if api_key not in settings.API_KEYS:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return api_key


# ── POST /scan  — submit new scan ────────────────────────────────────────────

@router.post("", response_model=ScanJobResponse, status_code=202)
async def submit_scan(
    request:     ScanRequest,
    background:  BackgroundTasks,
    _api_key:    str = Depends(verify_api_key),
):
    """
    Submit a new compliance scan job.
    Returns 202 Accepted immediately; results are populated asynchronously.
    """
    job_id = str(uuid.uuid4())
    now    = datetime.now(timezone.utc).isoformat()

    all_check_ids = [c["id"] for c in REGISTERED_CHECKS]
    selected      = request.checks if request.checks else all_check_ids

    job = {
        "job_id":      job_id,
        "status":      JobStatus.PENDING.value,
        "account_ids": request.account_ids,
        "regions":     request.regions,
        "checks":      selected,
        "created_at":  now,
        "completed_at": None,
        "total_checks": 0,
        "passed":      0,
        "failed":      0,
        "errors":      0,
    }
    repo.create_job(job)
    logger.info("Scan job submitted job_id=%s accounts=%s", job_id, request.account_ids)

    background.add_task(
        _execute_scan,
        job_id       = job_id,
        account_ids  = request.account_ids,
        regions      = request.regions,
        check_ids    = selected,
    )

    return ScanJobResponse(**job)


async def _execute_scan(job_id: str, account_ids: List[str], regions: List[str], check_ids: List[str]):
    """Background task: fan-out Lambda calls, persist results, update job status."""
    repo.update_job(job_id, {"status": JobStatus.RUNNING.value})
    try:
        results = await run_checks_async(job_id, account_ids, regions, check_ids)

        passed = sum(1 for r in results if r.status == CheckStatus.PASSED)
        failed = sum(1 for r in results if r.status == CheckStatus.FAILED)
        errors = sum(1 for r in results if r.status == CheckStatus.ERROR)

        for r in results:
            repo.save_result({
                "job_id":      job_id,
                "check_id":    r.check_id,
                "account_id":  r.account_id,
                "region":      r.region,
                "status":      r.status.value,
                "message":     r.message,
                "resource_id": r.resource_id or "",
                "remediation": r.remediation or "",
                "severity":    r.severity,
                "timestamp":   r.timestamp,
            })

        final_status = (
            JobStatus.COMPLETED if errors == 0 else JobStatus.PARTIAL
        )
        repo.update_job(job_id, {
            "status":       final_status.value,
            "total_checks": len(results),
            "passed":       passed,
            "failed":       failed,
            "errors":       errors,
            "completed_at": datetime.now(timezone.utc).isoformat(),
        })
        logger.info("Scan complete job_id=%s passed=%d failed=%d errors=%d", job_id, passed, failed, errors)

    except Exception:
        logger.exception("Unhandled error during scan job_id=%s", job_id)
        repo.update_job(job_id, {"status": JobStatus.FAILED.value})


# ── GET /scan  — list all jobs ───────────────────────────────────────────────

@router.get("", response_model=List[ScanSummaryResponse])
async def list_scans(_api_key: str = Depends(verify_api_key)):
    jobs = repo.list_jobs()
    out  = []
    for j in jobs:
        total  = j.get("total_checks", 0)
        passed = j.get("passed", 0)
        out.append(ScanSummaryResponse(
            job_id       = j["job_id"],
            status       = JobStatus(j["status"]),
            total_checks = total,
            passed       = passed,
            failed       = j.get("failed", 0),
            errors       = j.get("errors", 0),
            pass_rate    = round(passed / total * 100, 1) if total else 0.0,
            created_at   = j["created_at"],
            completed_at = j.get("completed_at"),
        ))
    return out


# ── GET /scan/{job_id} — get job + results ───────────────────────────────────

@router.get("/{job_id}", response_model=ScanJobResponse)
async def get_scan(job_id: str, _api_key: str = Depends(verify_api_key)):
    job = repo.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Scan job {job_id} not found")

    raw_results = repo.get_results_for_job(job_id)
    from app.schemas import CheckResult
    results = [
        CheckResult(
            check_id    = r["check_id"],
            check_name  = next((c["name"] for c in REGISTERED_CHECKS if c["id"] == r["check_id"]), r["check_id"]),
            account_id  = r["account_id"],
            region      = r["region"],
            status      = CheckStatus(r["status"]),
            resource_id = r.get("resource_id"),
            message     = r["message"],
            remediation = r.get("remediation"),
            severity    = r.get("severity", "MEDIUM"),
            timestamp   = r["timestamp"],
        )
        for r in raw_results
    ]
    total  = job.get("total_checks", 0)
    passed = job.get("passed", 0)
    return ScanJobResponse(
        job_id       = job["job_id"],
        status       = JobStatus(job["status"]),
        account_ids  = job["account_ids"],
        regions      = job["regions"],
        checks       = job["checks"],
        created_at   = job["created_at"],
        completed_at = job.get("completed_at"),
        total_checks = total,
        passed       = passed,
        failed       = job.get("failed", 0),
        errors       = job.get("errors", 0),
        results      = results,
    )


# ── POST /scan/{job_id}/rescan ───────────────────────────────────────────────

@router.post("/{job_id}/rescan", response_model=ScanJobResponse, status_code=202)
async def rescan(
    job_id:     str,
    request:    RescanRequest,
    background: BackgroundTasks,
    _api_key:   str = Depends(verify_api_key),
):
    job = repo.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    check_ids = request.checks or job["checks"]
    repo.update_job(job_id, {"status": JobStatus.PENDING.value})
    background.add_task(
        _execute_scan,
        job_id      = job_id,
        account_ids = job["account_ids"],
        regions     = job["regions"],
        check_ids   = check_ids,
    )
    return await get_scan(job_id, _api_key)
