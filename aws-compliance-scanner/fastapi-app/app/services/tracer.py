"""
OpenTelemetry tracer setup.
Exports traces to the OpenTelemetry Collector sidecar (or Jaeger / AWS X-Ray).
"""
from opentelemetry                         import trace
from opentelemetry.sdk.trace               import TracerProvider
from opentelemetry.sdk.trace.export        import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.resources           import Resource, SERVICE_NAME, SERVICE_VERSION
from app.config import get_settings

settings = get_settings()


def setup_tracing(app):
    """Call once at FastAPI startup."""
    if not settings.ENABLE_TRACING:
        return

    resource = Resource.create({
        SERVICE_NAME:    settings.APP_NAME,
        SERVICE_VERSION: settings.APP_VERSION,
        "deployment.environment": settings.ENVIRONMENT,
        "deployment.slot":        settings.SLOT,
    })

    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=settings.OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    FastAPIInstrumentor.instrument_app(app)
    RequestsInstrumentor().instrument()
