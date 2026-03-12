"""
/scan routes — Submit and manage compliance scan jobs.
Step Functions Approach (Approach B)

The key difference from Approach A:
- No BackgroundTasks for Lambda invocation
- No asyncio/ThreadPool management
- Step Functions handles all orchestration
- FastAPI just triggers Step Functions and returns immediately
"""
import logging
import uuid
from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Security
from fastapi.security.api_key import APIKeyHeader

from app.config import get_settings
from app.database import ScanRepository
from app.schemas import (
    JobStatus,
    ScanRequest, ScanJobResponse, ScanSummaryResponse,
    RescanRequest, ExecutionStatusResponse,
)
from app.services.stepfunctions_invoker import (
    run_checks_via_stepfunctions,
    get_stepfunctions_invoker,
    REGISTERED_CHECKS,
)

logger   = logging.getLogger(__name__)
settings = get_settings()

router       = APIRouter(prefix="/scan", tags=["scan"])
api_key_hdr  = APIKeyHeader(name=settings.API_KEY_HEADER, auto_error=True)
repo         = ScanRepository()


def verify_api_key(api_key: str = Security(api_key_hdr)):
    if api_key not in settings.API_KEYS:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return api_key


# ── POST /scan — Submit new scan via Step Functions ──────────────────────────

@router.post("", response_model=ScanJobResponse, status_code=202)
async def submit_scan(
    request: ScanRequest,
    _api_key: str = Depends(verify_api_key),
):
    """
    Submit a new compliance scan job.
    
    Flow (Step Functions approach):
    1. Generate job_id
    2. Create job record in DynamoDB (status=PENDING)
    3. Start Step Functions execution (async)
    4. Return 202 Accepted immediately
    
    Step Functions then:
    - Updates job status to RUNNING
    - Routes to appropriate Lambda functions based on check_id
    - Executes checks in parallel (Map state)
    - Aggregates results
    - Updates job status to COMPLETED
    """
    job_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    all_check_ids = [c["id"] for c in REGISTERED_CHECKS]
    selected = request.checks if request.checks else all_check_ids

    # Create job record
    job = {
        "job_id": job_id,
        "status": JobStatus.PENDING.value,
        "account_ids": request.account_ids,
        "regions": request.regions,
        "checks": selected,
        "created_at": now,
        "completed_at": None,
        "total_checks": 0,
        "passed": 0,
        "failed": 0,
        "errors": 0,
        "execution_arn": None,  # Will be populated by Step Functions trigger
    }
    repo.create_job(job)
    logger.info("Scan job created job_id=%s accounts=%s", job_id, request.account_ids)

    # Trigger Step Functions execution
    try:
        execution_result = await run_checks_via_stepfunctions(
            job_id=job_id,
            account_ids=request.account_ids,
            regions=request.regions,
            check_ids=selected,
        )

        # Store execution ARN for tracking
        repo.update_job(job_id, {
            "execution_arn": execution_result["execution_arn"],
            "status": JobStatus.RUNNING.value,
        })

        logger.info(
            "Step Functions execution started job_id=%s execution_arn=%s",
            job_id,
            execution_result["execution_arn"],
        )

    except ValueError as e:
        # Execution already exists
        repo.update_job(job_id, {"status": JobStatus.FAILED.value})
        raise HTTPException(status_code=409, detail=str(e))

    except Exception as e:
        logger.exception("Failed to start Step Functions execution: %s", e)
        repo.update_job(job_id, {"status": JobStatus.FAILED.value})
        raise HTTPException(status_code=500, detail="Failed to start scan execution")

    return ScanJobResponse(**repo.get_job(job_id))


# ── GET /scan — List all jobs ────────────────────────────────────────────────

@router.get("", response_model=List[ScanSummaryResponse])
async def list_scans(_api_key: str = Depends(verify_api_key)):
    """List all scan jobs with summary statistics."""
    jobs = repo.list_jobs()
    out = []
    for j in jobs:
        total = j.get("total_checks", 0)
        passed = j.get("passed", 0)
        out.append(ScanSummaryResponse(
            job_id=j["job_id"],
            status=JobStatus(j["status"]),
            total_checks=total,
            passed=passed,
            failed=j.get("failed", 0),
            errors=j.get("errors", 0),
            pass_rate=round(passed / total * 100, 1) if total else 0.0,
            created_at=j["created_at"],
            completed_at=j.get("completed_at"),
            execution_arn=j.get("execution_arn"),
        ))
    return out


# ── GET /scan/{job_id} — Get job details + results ───────────────────────────

@router.get("/{job_id}", response_model=ScanJobResponse)
async def get_scan(job_id: str, _api_key: str = Depends(verify_api_key)):
    """Get scan job details and results."""
    job = repo.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Scan job not found")

    # Optionally refresh status from Step Functions if still running
    if job.get("status") == JobStatus.RUNNING.value and job.get("execution_arn"):
        try:
            invoker = get_stepfunctions_invoker()
            sfn_status = invoker.get_execution_status(job["execution_arn"])
            
            # Map Step Functions status to job status
            if sfn_status["status"] == "SUCCEEDED":
                # Results should already be in DynamoDB via the state machine
                job = repo.get_job(job_id)  # Refresh
            elif sfn_status["status"] in ("FAILED", "TIMED_OUT", "ABORTED"):
                repo.update_job(job_id, {
                    "status": JobStatus.FAILED.value,
                    "error_message": sfn_status.get("error", "Unknown error"),
                })
                job = repo.get_job(job_id)
        except Exception as e:
            logger.warning("Failed to refresh Step Functions status: %s", e)

    # Get results
    results = repo.get_results(job_id)
    job["results"] = results

    return ScanJobResponse(**job)


# ── GET /scan/{job_id}/execution — Get Step Functions execution status ───────

@router.get("/{job_id}/execution", response_model=ExecutionStatusResponse)
async def get_execution_status(job_id: str, _api_key: str = Depends(verify_api_key)):
    """
    Get the Step Functions execution status for a scan job.
    
    This provides more detailed execution information than the job status,
    including execution timeline and any errors.
    """
    job = repo.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Scan job not found")

    execution_arn = job.get("execution_arn")
    if not execution_arn:
        raise HTTPException(status_code=400, detail="No execution ARN for this job")

    invoker = get_stepfunctions_invoker()
    status = invoker.get_execution_status(execution_arn)

    return ExecutionStatusResponse(
        job_id=job_id,
        execution_arn=execution_arn,
        status=status["status"],
        start_date=status.get("start_date"),
        stop_date=status.get("stop_date"),
        error=status.get("error"),
        cause=status.get("cause"),
    )


# ── POST /scan/{job_id}/stop — Stop a running scan ───────────────────────────

@router.post("/{job_id}/stop")
async def stop_scan(job_id: str, _api_key: str = Depends(verify_api_key)):
    """
    Stop a running scan job.
    
    This stops the Step Functions execution, which will stop any
    pending Lambda invocations. Already-running Lambda functions
    will complete.
    """
    job = repo.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Scan job not found")

    if job.get("status") != JobStatus.RUNNING.value:
        raise HTTPException(
            status_code=400,
            detail=f"Job is not running (status: {job.get('status')})",
        )

    execution_arn = job.get("execution_arn")
    if not execution_arn:
        raise HTTPException(status_code=400, detail="No execution ARN for this job")

    invoker = get_stepfunctions_invoker()
    success = invoker.stop_execution(execution_arn, cause="User requested stop")

    if success:
        repo.update_job(job_id, {
            "status": JobStatus.FAILED.value,
            "error_message": "Scan stopped by user",
            "completed_at": datetime.now(timezone.utc).isoformat(),
        })
        return {"message": "Scan stopped successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to stop scan")


# ── POST /scan/{job_id}/rescan — Rescan specific checks ──────────────────────

@router.post("/{job_id}/rescan", response_model=ScanJobResponse, status_code=202)
async def rescan(
    job_id: str,
    request: RescanRequest,
    _api_key: str = Depends(verify_api_key),
):
    """
    Rescan specific checks from a previous scan.
    
    Creates a new job with the same accounts/regions but
    only the specified checks. Useful for re-running failed checks.
    """
    original_job = repo.get_job(job_id)
    if not original_job:
        raise HTTPException(status_code=404, detail="Original scan job not found")

    # Create new job based on original
    new_job_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    # Use specified checks or re-run failed checks from original
    checks_to_run = request.checks
    if not checks_to_run and request.only_failed:
        # Get failed checks from original job
        results = repo.get_results(job_id)
        checks_to_run = [r["check_id"] for r in results if r.get("status") == "FAILED"]

    if not checks_to_run:
        raise HTTPException(status_code=400, detail="No checks specified for rescan")

    new_job = {
        "job_id": new_job_id,
        "status": JobStatus.PENDING.value,
        "account_ids": original_job["account_ids"],
        "regions": original_job["regions"],
        "checks": checks_to_run,
        "created_at": now,
        "completed_at": None,
        "total_checks": 0,
        "passed": 0,
        "failed": 0,
        "errors": 0,
        "parent_job_id": job_id,  # Link to original
        "execution_arn": None,
    }
    repo.create_job(new_job)

    # Start Step Functions execution
    try:
        execution_result = await run_checks_via_stepfunctions(
            job_id=new_job_id,
            account_ids=original_job["account_ids"],
            regions=original_job["regions"],
            check_ids=checks_to_run,
        )
        repo.update_job(new_job_id, {
            "execution_arn": execution_result["execution_arn"],
            "status": JobStatus.RUNNING.value,
        })
    except Exception as e:
        logger.exception("Failed to start rescan: %s", e)
        repo.update_job(new_job_id, {"status": JobStatus.FAILED.value})
        raise HTTPException(status_code=500, detail="Failed to start rescan")

    return ScanJobResponse(**repo.get_job(new_job_id))
