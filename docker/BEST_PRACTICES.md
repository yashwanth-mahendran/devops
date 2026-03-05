# Dockerfile Best Practices

A comprehensive guide to writing production-grade Dockerfiles following industry best practices.

---

## Table of Contents

1. [Base Image Selection](#1-base-image-selection)
2. [Multi-Stage Builds](#2-multi-stage-builds)
3. [Layer Optimization](#3-layer-optimization)
4. [Security Best Practices](#4-security-best-practices)
5. [Caching Optimization](#5-caching-optimization)
6. [Environment Variables](#6-environment-variables)
7. [Health Checks](#7-health-checks)
8. [Labels and Metadata](#8-labels-and-metadata)
9. [Logging Best Practices](#9-logging-best-practices)
10. [Common Anti-Patterns](#10-common-anti-patterns)

---

## 1. Base Image Selection

### ✅ DO: Use Official, Minimal Base Images

```dockerfile
# Good - Alpine for smallest footprint
FROM node:20-alpine

# Good - Slim variants for balance
FROM python:3.12-slim-bookworm

# Good - Distroless for security
FROM gcr.io/distroless/java21-debian12
```

### ❌ DON'T: Use Generic or Unversioned Tags

```dockerfile
# Bad - Unpredictable behavior
FROM node:latest

# Bad - Large image size
FROM ubuntu:22.04

# Bad - No version pinning
FROM python
```

### Image Size Comparison

| Base Image | Approximate Size |
|------------|------------------|
| `alpine:3.19` | ~7 MB |
| `node:20-alpine` | ~130 MB |
| `node:20-slim` | ~250 MB |
| `node:20` | ~1.1 GB |
| `python:3.12-alpine` | ~50 MB |
| `python:3.12-slim` | ~130 MB |
| `python:3.12` | ~1 GB |

---

## 2. Multi-Stage Builds

Multi-stage builds separate build-time dependencies from runtime, drastically reducing final image size.

### ✅ Good Practice

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production (only runtime dependencies)
FROM node:20-alpine AS production
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/index.js"]
```

### Benefits
- **Smaller Images**: Build tools not included in final image
- **Security**: Fewer packages = smaller attack surface
- **Caching**: Better layer caching between stages

---

## 3. Layer Optimization

### ✅ DO: Combine Related Commands

```dockerfile
# Good - Single layer for apt operations
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
```

### ❌ DON'T: Create Unnecessary Layers

```dockerfile
# Bad - Multiple layers, no cleanup
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y wget
```

### Layer Order (Most Stable → Least Stable)

```dockerfile
# 1. Base image and system packages (rarely change)
FROM node:20-alpine
RUN apk add --no-cache curl

# 2. Dependencies (change occasionally)
COPY package*.json ./
RUN npm ci --only=production

# 3. Application code (changes frequently)
COPY . .

# 4. Build step
RUN npm run build
```

---

## 4. Security Best Practices

### 4.1 Run as Non-Root User

```dockerfile
# Create dedicated user
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

# Set ownership
COPY --chown=appuser:appgroup . .

# Switch to non-root user
USER appuser
```

### 4.2 Use Specific Image Digests for Production

```dockerfile
# Pin to exact image version using SHA256 digest
FROM node:20-alpine@sha256:a1b2c3d4e5f6...
```

### 4.3 Scan for Vulnerabilities

```bash
# Using Docker Scout
docker scout cves myimage:latest

# Using Trivy
trivy image myimage:latest

# Using Snyk
snyk container test myimage:latest
```

### 4.4 .dockerignore File

```dockerignore
# Always include these
.git
.gitignore
Dockerfile*
docker-compose*
.dockerignore
README.md
.env*
*.log
node_modules
__pycache__
.pytest_cache
.coverage
.nyc_output
dist
build
target
*.jar
.idea
.vscode
```

### 4.5 Avoid Secrets in Images

```dockerfile
# ❌ NEVER do this
ENV API_KEY=secret123
COPY secrets.txt /app/

# ✅ Use build arguments for non-sensitive config
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# ✅ Use Docker secrets or mount at runtime
# docker run -e API_KEY=$(cat secrets.txt) myapp
```

---

## 5. Caching Optimization

### Copy Dependency Files First

```dockerfile
# Dependencies change less frequently than code
COPY package*.json ./
RUN npm ci

# Code changes more frequently
COPY . .
```

### Use BuildKit Cache Mounts

```dockerfile
# syntax=docker/dockerfile:1.4

# Cache pip packages
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Cache npm packages
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Cache Maven repository
RUN --mount=type=cache,target=/root/.m2 \
    mvn package
```

### Enable BuildKit

```bash
# Set environment variable
export DOCKER_BUILDKIT=1

# Or use docker buildx
docker buildx build -t myapp .
```

---

## 6. Environment Variables

### Use ARG for Build-Time Variables

```dockerfile
# Build-time variable
ARG APP_VERSION=1.0.0
ARG BUILD_DATE

# Convert to runtime if needed
ENV APP_VERSION=$APP_VERSION
```

### Use ENV for Runtime Variables

```dockerfile
# Environment variables with defaults
ENV NODE_ENV=production \
    PORT=3000 \
    LOG_LEVEL=info
```

### Best Practice: Combine with Defaults

```dockerfile
# Build args with defaults
ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-alpine

# Runtime with overridable defaults
ENV APP_PORT=${APP_PORT:-3000}
```

---

## 7. Health Checks

### Basic Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

### Health Check Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--interval` | Time between checks | 30s |
| `--timeout` | Max time for check | 30s |
| `--start-period` | Initialization grace period | 0s |
| `--retries` | Consecutive failures before unhealthy | 3 |

### Language-Specific Health Checks

```dockerfile
# Node.js
HEALTHCHECK CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Python/FastAPI
HEALTHCHECK CMD curl --fail http://localhost:8000/health || exit 1

# Java/Spring Boot
HEALTHCHECK CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1
```

---

## 8. Labels and Metadata

### OCI Standard Labels

```dockerfile
LABEL org.opencontainers.image.title="My Application"
LABEL org.opencontainers.image.description="Production-ready application"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.vendor="My Company"
LABEL org.opencontainers.image.source="https://github.com/mycompany/myapp"
LABEL org.opencontainers.image.created="2024-01-15T10:00:00Z"
LABEL org.opencontainers.image.authors="devops@example.com"
```

### Dynamic Labels with Build Args

```dockerfile
ARG BUILD_DATE
ARG GIT_COMMIT
ARG VERSION

LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.revision=$GIT_COMMIT
LABEL org.opencontainers.image.version=$VERSION
```

```bash
# Build with dynamic labels
docker build \
    --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
    --build-arg GIT_COMMIT=$(git rev-parse HEAD) \
    --build-arg VERSION=1.0.0 \
    -t myapp .
```

---

## 9. Logging Best Practices

### Log to STDOUT/STDERR

```dockerfile
# Redirect logs to stdout/stderr
RUN ln -sf /dev/stdout /var/log/app/access.log && \
    ln -sf /dev/stderr /var/log/app/error.log
```

### Application Configuration

```python
# Python - configure logging to stdout
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
```

```javascript
// Node.js - use console for Docker logging
console.log('Application started');
console.error('Error occurred');
```

---

## 10. Common Anti-Patterns

### ❌ Anti-Pattern: Running as Root

```dockerfile
# Bad
FROM node:20-alpine
COPY . .
CMD ["node", "index.js"]  # Running as root!
```

### ❌ Anti-Pattern: Using ADD Instead of COPY

```dockerfile
# Bad - ADD has extra features you probably don't need
ADD . /app

# Good - COPY is explicit and predictable
COPY . /app

# Only use ADD for URLs or tar extraction
ADD https://example.com/file.tar.gz /app/
```

### ❌ Anti-Pattern: Not Using .dockerignore

```dockerfile
# Without .dockerignore, COPY might include:
# - node_modules (huge!)
# - .git directory
# - local environment files
# - IDE configuration
COPY . .
```

### ❌ Anti-Pattern: Hardcoding Values

```dockerfile
# Bad
ENV DATABASE_URL=postgres://user:pass@localhost:5432/db

# Good - use runtime environment variables
ENV DATABASE_URL=${DATABASE_URL}
```

### ❌ Anti-Pattern: Installing Unnecessary Packages

```dockerfile
# Bad - includes man pages, docs, etc.
RUN apt-get install -y curl

# Good - minimal install
RUN apt-get install -y --no-install-recommends curl
```

---

## Quick Reference Checklist

- [ ] Use minimal, official base images
- [ ] Implement multi-stage builds
- [ ] Run as non-root user
- [ ] Create proper .dockerignore
- [ ] Order layers by change frequency
- [ ] Use specific version tags
- [ ] Implement health checks
- [ ] Add descriptive labels
- [ ] Never store secrets in images
- [ ] Clean up unnecessary files in layers
- [ ] Scan images for vulnerabilities

---

## Further Reading

- [Docker Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Hadolint - Dockerfile Linter](https://github.com/hadolint/hadolint)
