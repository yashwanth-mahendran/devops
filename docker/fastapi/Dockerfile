# ============================================
# FastAPI Dockerfile - Production Ready
# ============================================
# This Dockerfile demonstrates best practices for
# containerizing Python FastAPI applications

# ============================================
# STAGE 1: Build Stage
# ============================================
FROM python:3.12-slim-bookworm AS builder

# Set environment variables for Python
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements first (layer caching optimization)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# ============================================
# STAGE 2: Production Stage
# ============================================
FROM python:3.12-slim-bookworm AS production

# Security - Add labels for container metadata
LABEL maintainer="devops@example.com"
LABEL version="1.0"
LABEL description="Production FastAPI Application"

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    PATH="/opt/venv/bin:$PATH" \
    APP_ENV=production \
    PORT=8000

# Security - Create non-root user
RUN groupadd -g 1001 fastapi && \
    useradd -u 1001 -g fastapi -s /bin/bash -m fastapi

# Set working directory
WORKDIR /app

# Install runtime dependencies only (if needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Copy application code
COPY --chown=fastapi:fastapi . .

# Switch to non-root user
USER fastapi

# Expose application port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl --fail http://localhost:8000/health || exit 1

# Run with uvicorn (production ASGI server)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]

# ============================================
# ALTERNATIVE: With Gunicorn + Uvicorn workers
# ============================================
# CMD ["gunicorn", "main:app", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8000"]

# ============================================
# ALTERNATIVE: Development Stage
# ============================================
# FROM python:3.12-slim-bookworm AS development
# WORKDIR /app
# COPY requirements-dev.txt requirements.txt ./
# RUN pip install -r requirements-dev.txt
# COPY . .
# EXPOSE 8000
# CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# ============================================
# ALTERNATIVE: Using Poetry
# ============================================
# FROM python:3.12-slim-bookworm AS poetry-builder
# ENV POETRY_NO_INTERACTION=1 \
#     POETRY_VIRTUALENVS_IN_PROJECT=1 \
#     POETRY_HOME="/opt/poetry"
# ENV PATH="$POETRY_HOME/bin:$PATH"
# RUN pip install poetry
# WORKDIR /app
# COPY pyproject.toml poetry.lock ./
# RUN poetry install --only main --no-root
# COPY . .
# RUN poetry install --only-root
