"""
AWS Compliance Scanner — FastAPI Application
Approach B: Step Functions Orchestration

This application exposes a REST API for triggering compliance scans.
Lambda orchestration is delegated to AWS Step Functions.
"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import get_settings
from app.routers import scan, health

# Configure logging
settings = get_settings()
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


# ── OpenTelemetry Setup ──────────────────────────────────────────────────────

def setup_tracing():
    """Initialize OpenTelemetry tracing."""
    if not settings.ENABLE_TRACING:
        logger.info("Tracing disabled")
        return

    try:
        from opentelemetry import trace
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.botocore import BotocoreInstrumentor

        # Set up tracer provider
        provider = TracerProvider()
        processor = BatchSpanProcessor(
            OTLPSpanExporter(endpoint=settings.OTEL_EXPORTER_OTLP_ENDPOINT)
        )
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)

        # Instrument botocore (boto3)
        BotocoreInstrumentor().instrument()

        logger.info("Tracing initialized: %s", settings.OTEL_EXPORTER_OTLP_ENDPOINT)
    except Exception as e:
        logger.warning("Failed to initialize tracing: %s", e)


# ── Lifespan ─────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    # Startup
    logger.info(
        "Starting %s v%s (slot=%s, env=%s)",
        settings.APP_NAME,
        settings.APP_VERSION,
        settings.SLOT,
        settings.ENVIRONMENT,
    )
    setup_tracing()
    yield
    # Shutdown
    logger.info("Shutting down %s", settings.APP_NAME)


# ── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="AWS Compliance Scanner",
    description="Scan AWS resources for security and operational compliance (Step Functions approach)",
    version=settings.APP_VERSION,
    docs_url="/docs" if settings.ENVIRONMENT != "production" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT != "production" else None,
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics
Instrumentator().instrument(app).expose(app, include_in_schema=False)

# Routers
app.include_router(scan.router, prefix="/api/v1")
app.include_router(health.router)


# ── Root Endpoint ────────────────────────────────────────────────────────────

@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "slot": settings.SLOT,
        "approach": "Step Functions Orchestration",
    }
