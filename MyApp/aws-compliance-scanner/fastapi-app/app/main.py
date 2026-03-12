"""
FastAPI Application Entry Point
AWS Compliance Scanner
"""
import logging
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import get_settings
from app.routers import health, scan
from app.services.tracer import setup_tracing

settings = get_settings()

logging.basicConfig(
    level   = settings.LOG_LEVEL,
    format  = "%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "Starting %s v%s  env=%s  slot=%s",
        settings.APP_NAME, settings.APP_VERSION,
        settings.ENVIRONMENT, settings.SLOT,
    )
    yield
    logger.info("Shutting down %s", settings.APP_NAME)


app = FastAPI(
    title       = "AWS Compliance Scanner",
    description = "Scans AWS resources across accounts/regions for best-practice compliance",
    version     = settings.APP_VERSION,
    docs_url    = "/api/docs",
    redoc_url   = "/api/redoc",
    openapi_url = "/api/openapi.json",
    lifespan    = lifespan,
)

# ── Middleware ────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins  = ["*"],
    allow_methods  = ["GET", "POST"],
    allow_headers  = ["*"],
)


@app.middleware("http")
async def add_request_id_and_timing(request: Request, call_next):
    import uuid
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    start = time.time()
    response = await call_next(request)
    duration_ms = int((time.time() - start) * 1000)
    response.headers["x-request-id"]   = request_id
    response.headers["x-duration-ms"]  = str(duration_ms)
    response.headers["x-app-slot"]     = settings.SLOT
    logger.info(
        "method=%s path=%s status=%d duration_ms=%d request_id=%s",
        request.method, request.url.path, response.status_code, duration_ms, request_id,
    )
    return response


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled exception: %s", exc)
    return JSONResponse(status_code=500, content={"error": "Internal server error", "detail": str(exc)})


# ── Routes ────────────────────────────────────────────────────────────────────

app.include_router(health.router)
app.include_router(scan.router, prefix="/api/v1")

# ── Prometheus metrics ────────────────────────────────────────────────────────

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

# ── OpenTelemetry tracing ─────────────────────────────────────────────────────

setup_tracing(app)


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host    = "0.0.0.0",
        port    = 8080,
        workers = 4,
        log_config = None,
    )
