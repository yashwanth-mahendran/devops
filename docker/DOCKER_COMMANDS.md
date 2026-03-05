# Docker Commands Reference

Production-based and interview-focused Docker commands guide.

---

## Table of Contents

1. [Image Management](#1-image-management)
2. [Container Lifecycle](#2-container-lifecycle)
3. [Container Inspection & Debugging](#3-container-inspection--debugging)
4. [Networking](#4-networking)
5. [Volume Management](#5-volume-management)
6. [Docker Compose](#6-docker-compose)
7. [Registry Operations](#7-registry-operations)
8. [System Maintenance](#8-system-maintenance)
9. [Production Commands](#9-production-commands)
10. [Interview Questions & Scenarios](#10-interview-questions--scenarios)

---

## 1. Image Management

### Building Images

```bash
# Basic build
docker build -t myapp:1.0 .

# Build with no cache
docker build --no-cache -t myapp:1.0 .

# Build with build arguments
docker build --build-arg VERSION=1.0.0 -t myapp:1.0 .

# Build with specific Dockerfile
docker build -f Dockerfile.prod -t myapp:1.0 .

# Build for specific platform
docker build --platform linux/amd64 -t myapp:1.0 .

# Multi-platform build (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:1.0 .

# Build with target stage (multi-stage)
docker build --target builder -t myapp:builder .

# Build with labels
docker build --label version=1.0 --label maintainer=devops@example.com -t myapp:1.0 .
```

### Listing Images

```bash
# List all images
docker images

# List with specific format
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# List dangling images (untagged)
docker images -f "dangling=true"

# List images by reference
docker images "myapp*"

# Show image digests
docker images --digests

# List image IDs only
docker images -q
```

### Image Operations

```bash
# Tag an image
docker tag myapp:1.0 myregistry.com/myapp:1.0

# Remove an image
docker rmi myapp:1.0

# Force remove image
docker rmi -f myapp:1.0

# Remove all unused images
docker image prune -a

# Remove dangling images only
docker image prune

# Save image to tar file
docker save -o myapp.tar myapp:1.0

# Load image from tar file
docker load -i myapp.tar

# Show image history (layers)
docker history myapp:1.0

# Inspect image details
docker inspect myapp:1.0

# Get specific info with format
docker inspect --format='{{.Architecture}}' myapp:1.0
```

---

## 2. Container Lifecycle

### Running Containers

```bash
# Basic run
docker run myapp:1.0

# Run in detached mode (background)
docker run -d myapp:1.0

# Run with name
docker run -d --name myapp-container myapp:1.0

# Run with port mapping
docker run -d -p 8080:80 myapp:1.0

# Run with multiple port mappings
docker run -d -p 8080:80 -p 443:443 myapp:1.0

# Run with environment variables
docker run -d -e DATABASE_URL=postgres://... myapp:1.0

# Run with env file
docker run -d --env-file .env myapp:1.0

# Run with volume mount
docker run -d -v /host/path:/container/path myapp:1.0

# Run with named volume
docker run -d -v mydata:/app/data myapp:1.0

# Run with bind mount (explicit syntax)
docker run -d --mount type=bind,source=/host/path,target=/container/path myapp:1.0

# Run with tmpfs mount (in-memory)
docker run -d --tmpfs /tmp myapp:1.0

# Run with resource limits
docker run -d --memory=512m --cpus=0.5 myapp:1.0

# Run with restart policy
docker run -d --restart=always myapp:1.0

# Run interactive with terminal
docker run -it myapp:1.0 /bin/sh

# Run and remove after exit
docker run --rm myapp:1.0

# Run with specific user
docker run -u 1000:1000 myapp:1.0

# Run with hostname
docker run -d --hostname myhost myapp:1.0

# Run with specific network
docker run -d --network mynetwork myapp:1.0

# Run with read-only filesystem
docker run -d --read-only myapp:1.0

# Run with security options
docker run -d --security-opt no-new-privileges myapp:1.0
```

### Container Management

```bash
# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# List container IDs only
docker ps -q

# List with specific format
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Start a stopped container
docker start myapp-container

# Stop a running container
docker stop myapp-container

# Stop with timeout (seconds)
docker stop -t 30 myapp-container

# Restart a container
docker restart myapp-container

# Pause a container
docker pause myapp-container

# Unpause a container
docker unpause myapp-container

# Kill a container (SIGKILL)
docker kill myapp-container

# Remove a stopped container
docker rm myapp-container

# Force remove running container
docker rm -f myapp-container

# Remove all stopped containers
docker container prune

# Remove all containers (force)
docker rm -f $(docker ps -aq)

# Rename a container
docker rename old-name new-name

# Update container resources
docker update --memory=1g --cpus=1 myapp-container

# Wait for container to stop
docker wait myapp-container
```

---

## 3. Container Inspection & Debugging

### Logs

```bash
# View container logs
docker logs myapp-container

# Follow logs (real-time)
docker logs -f myapp-container

# Show last N lines
docker logs --tail 100 myapp-container

# Show logs with timestamps
docker logs -t myapp-container

# Show logs since time
docker logs --since 2024-01-01T00:00:00 myapp-container

# Show logs in last 10 minutes
docker logs --since 10m myapp-container
```

### Inspection

```bash
# Inspect container details
docker inspect myapp-container

# Get container IP address
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' myapp-container

# Get container health status
docker inspect -f '{{.State.Health.Status}}' myapp-container

# Get mount points
docker inspect -f '{{json .Mounts}}' myapp-container | jq

# Get environment variables
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' myapp-container

# Get container PID
docker inspect -f '{{.State.Pid}}' myapp-container
```

### Exec into Container

```bash
# Execute command in running container
docker exec myapp-container ls -la

# Interactive shell
docker exec -it myapp-container /bin/sh

# Interactive bash (if available)
docker exec -it myapp-container /bin/bash

# Execute as specific user
docker exec -u root myapp-container whoami

# Execute with environment variable
docker exec -e MY_VAR=value myapp-container env

# Execute in working directory
docker exec -w /app myapp-container pwd
```

### Resource Usage

```bash
# Show container resource stats
docker stats

# Stats for specific container
docker stats myapp-container

# One-time stats (no streaming)
docker stats --no-stream

# Show stats with specific format
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Show running processes in container
docker top myapp-container

# Show filesystem changes
docker diff myapp-container
```

### Copy Files

```bash
# Copy from container to host
docker cp myapp-container:/app/file.txt ./file.txt

# Copy from host to container
docker cp ./file.txt myapp-container:/app/file.txt

# Copy entire directory
docker cp myapp-container:/app/logs ./logs
```

---

## 4. Networking

### Network Management

```bash
# List networks
docker network ls

# Create network (bridge)
docker network create mynetwork

# Create network with driver
docker network create --driver bridge mynetwork

# Create network with subnet
docker network create --subnet=172.20.0.0/16 mynetwork

# Create overlay network (Swarm)
docker network create --driver overlay myoverlay

# Inspect network
docker network inspect mynetwork

# Remove network
docker network rm mynetwork

# Prune unused networks
docker network prune

# Connect container to network
docker network connect mynetwork myapp-container

# Disconnect container from network
docker network disconnect mynetwork myapp-container

# Connect with alias
docker network connect --alias myalias mynetwork myapp-container
```

### Network Inspection

```bash
# Show containers in network
docker network inspect -f '{{range .Containers}}{{.Name}}{{end}}' mynetwork

# Show network driver
docker network inspect -f '{{.Driver}}' mynetwork

# Show subnet
docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' mynetwork

# Show port mappings
docker port myapp-container
```

---

## 5. Volume Management

```bash
# List volumes
docker volume ls

# Create volume
docker volume create myvolume

# Create volume with driver options
docker volume create --driver local --opt type=nfs --opt o=addr=192.168.1.1,rw --opt device=:/path/to/dir myvolume

# Inspect volume
docker volume inspect myvolume

# Remove volume
docker volume rm myvolume

# Remove all unused volumes
docker volume prune

# Remove all volumes (force)
docker volume prune -a

# Get volume mount point
docker volume inspect -f '{{.Mountpoint}}' myvolume

# Backup volume to tar
docker run --rm -v myvolume:/data -v $(pwd):/backup alpine tar cvf /backup/myvolume.tar /data

# Restore volume from tar
docker run --rm -v myvolume:/data -v $(pwd):/backup alpine tar xvf /backup/myvolume.tar -C /
```

---

## 6. Docker Compose

### Basic Commands

```bash
# Start services
docker compose up

# Start in detached mode
docker compose up -d

# Start specific service
docker compose up -d web

# Build and start
docker compose up --build

# Stop services
docker compose down

# Stop and remove volumes
docker compose down -v

# Stop and remove images
docker compose down --rmi all

# View logs
docker compose logs

# Follow logs
docker compose logs -f

# Logs for specific service
docker compose logs -f web
```

### Service Management

```bash
# List services
docker compose ps

# Start specific service
docker compose start web

# Stop specific service
docker compose stop web

# Restart service
docker compose restart web

# Scale service
docker compose up -d --scale web=3

# Execute command in service
docker compose exec web sh

# Run one-off command
docker compose run --rm web npm test

# View service config
docker compose config

# Pull images
docker compose pull

# Build images
docker compose build

# Build without cache
docker compose build --no-cache
```

### Environment and Profiles

```bash
# Use specific compose file
docker compose -f docker-compose.prod.yml up -d

# Use multiple compose files
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Use specific env file
docker compose --env-file .env.prod up -d

# Use profile
docker compose --profile debug up -d

# Set project name
docker compose -p myproject up -d
```

---

## 7. Registry Operations

### Docker Hub

```bash
# Login to Docker Hub
docker login

# Login to specific registry
docker login registry.example.com

# Logout
docker logout

# Push image
docker push myusername/myapp:1.0

# Pull image
docker pull myusername/myapp:1.0

# Search Docker Hub
docker search nginx
```

### Private Registry

```bash
# Login to private registry
docker login registry.example.com

# Tag for private registry
docker tag myapp:1.0 registry.example.com/myapp:1.0

# Push to private registry
docker push registry.example.com/myapp:1.0

# Pull from private registry
docker pull registry.example.com/myapp:1.0
```

### AWS ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Tag for ECR
docker tag myapp:1.0 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0

# Push to ECR
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0
```

---

## 8. System Maintenance

### Cleanup Commands

```bash
# Remove all unused resources (dangerous!)
docker system prune -a

# Remove unused resources without prompt
docker system prune -af

# Remove including volumes
docker system prune -a --volumes

# Remove dangling images only
docker image prune

# Remove all unused images
docker image prune -a

# Remove stopped containers
docker container prune

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# Remove build cache
docker builder prune

# Remove all build cache
docker builder prune -a
```

### System Information

```bash
# Show Docker system info
docker system info

# Show Docker version
docker version

# Show disk usage
docker system df

# Show detailed disk usage
docker system df -v

# Show Docker daemon events
docker system events

# Show events with filters
docker system events --filter 'type=container'

# Show events since time
docker system events --since '2024-01-01T00:00:00'
```

---

## 9. Production Commands

### Health Monitoring

```bash
# Check container health status
docker inspect --format='{{json .State.Health}}' myapp-container | jq

# List unhealthy containers
docker ps --filter health=unhealthy

# Watch container resource usage
watch docker stats --no-stream

# Check if container is running
docker inspect -f '{{.State.Running}}' myapp-container

# Get container uptime
docker inspect -f '{{.State.StartedAt}}' myapp-container
```

### Graceful Deployment

```bash
# Stop with extended timeout for graceful shutdown
docker stop -t 60 myapp-container

# Update container without downtime (using docker compose)
docker compose up -d --no-deps --build web

# Rolling update (Swarm)
docker service update --image myapp:2.0 myservice
```

### Backup & Restore

```bash
# Commit container to image (not recommended for production)
docker commit myapp-container myapp-backup:$(date +%Y%m%d)

# Export container filesystem
docker export myapp-container > container-backup.tar

# Import container filesystem
docker import container-backup.tar myapp-restored:1.0

# Backup volume
docker run --rm \
    -v myvolume:/source:ro \
    -v $(pwd):/backup \
    alpine tar -czf /backup/volume-backup.tar.gz -C /source .

# Restore volume
docker run --rm \
    -v myvolume:/target \
    -v $(pwd):/backup \
    alpine tar -xzf /backup/volume-backup.tar.gz -C /target
```

### Security Scanning

```bash
# Scan image with Docker Scout
docker scout cves myapp:1.0

# Quick vulnerability overview
docker scout quickview myapp:1.0

# Compare vulnerabilities between images
docker scout compare myapp:1.0 myapp:2.0

# Scan with Trivy
trivy image myapp:1.0

# Scan with Snyk
snyk container test myapp:1.0
```

### Resource Constraints

```bash
# Run with memory limit
docker run -d --memory=512m myapp:1.0

# Run with memory + swap limit
docker run -d --memory=512m --memory-swap=1g myapp:1.0

# Run with CPU limit
docker run -d --cpus=0.5 myapp:1.0

# Run with CPU shares (relative weight)
docker run -d --cpu-shares=512 myapp:1.0

# Run with PID limit
docker run -d --pids-limit=100 myapp:1.0

# Update running container limits
docker update --memory=1g --cpus=2 myapp-container
```

---

## 10. Interview Questions & Scenarios

### Q1: How do you reduce Docker image size?

```bash
# 1. Use multi-stage builds
# 2. Use smaller base images (alpine, slim, distroless)
# 3. Minimize layers
# 4. Clean up in same layer
# 5. Use .dockerignore

# Check image size
docker images myapp:1.0 --format "{{.Size}}"

# Analyze layers
docker history myapp:1.0

# Use dive tool for analysis
dive myapp:1.0
```

### Q2: How do you troubleshoot a container that keeps restarting?

```bash
# Check container status
docker ps -a

# Check exit code
docker inspect -f '{{.State.ExitCode}}' myapp-container

# Check OOM killed
docker inspect -f '{{.State.OOMKilled}}' myapp-container

# View logs
docker logs --tail 200 myapp-container

# Check events
docker events --filter 'container=myapp-container' --since 10m

# Inspect full state
docker inspect myapp-container | jq '.State'

# Run interactively to debug
docker run -it --entrypoint /bin/sh myapp:1.0
```

### Q3: How do you secure Docker in production?

```bash
# 1. Run as non-root
docker run -u 1000:1000 myapp:1.0

# 2. Use read-only filesystem
docker run --read-only myapp:1.0

# 3. Drop capabilities
docker run --cap-drop ALL myapp:1.0

# 4. Limit resources
docker run --memory=512m --cpus=0.5 --pids-limit=50 myapp:1.0

# 5. Use security options
docker run --security-opt no-new-privileges myapp:1.0

# 6. Scan for vulnerabilities
docker scout cves myapp:1.0
```

### Q4: Explain Docker networking modes

```bash
# Bridge (default) - isolated network
docker run --network bridge myapp:1.0

# Host - use host network directly
docker run --network host myapp:1.0

# None - no networking
docker run --network none myapp:1.0

# Custom bridge - user-defined network
docker network create mynetwork
docker run --network mynetwork myapp:1.0

# Container - share network with another container
docker run --network container:other-container myapp:1.0
```

### Q5: How do you pass secrets to containers?

```bash
# Method 1: Environment variables (visible in inspect)
docker run -e SECRET_KEY=value myapp:1.0

# Method 2: Docker secrets (Swarm)
echo "mysecret" | docker secret create my_secret -
docker service create --secret my_secret myapp:1.0

# Method 3: Mount secret file (read-only)
docker run -v /path/to/secrets:/secrets:ro myapp:1.0

# Method 4: Use BuildKit secrets for build
docker build --secret id=mysecret,src=./secret.txt .
```

### Q6: Difference between CMD and ENTRYPOINT

```dockerfile
# ENTRYPOINT - defines the executable (harder to override)
ENTRYPOINT ["python", "app.py"]

# CMD - provides defaults (easily overridden)
CMD ["--port", "8000"]

# Together - ENTRYPOINT + CMD
ENTRYPOINT ["python", "app.py"]
CMD ["--port", "8000"]
# Results in: python app.py --port 8000

# Override CMD at runtime
docker run myapp:1.0 --port 9000
# Results in: python app.py --port 9000

# Override ENTRYPOINT at runtime
docker run --entrypoint /bin/sh myapp:1.0
```

### Q7: How do you debug network issues?

```bash
# Check container network settings
docker inspect -f '{{json .NetworkSettings}}' myapp-container | jq

# Test connectivity from container
docker exec myapp-container ping google.com

# Check DNS resolution
docker exec myapp-container nslookup api.example.com

# Check listening ports inside container
docker exec myapp-container netstat -tlnp

# Check host port bindings
docker port myapp-container

# Use network debugging container
docker run --rm --network container:myapp-container nicolaka/netshoot \
    tcpdump -i eth0
```

### Q8: What happens when a container uses too much memory?

```bash
# Without limit - can use all host memory
docker run myapp:1.0

# With limit - OOM killer terminates container
docker run --memory=512m myapp:1.0

# Check if OOM killed
docker inspect -f '{{.State.OOMKilled}}' myapp-container

# Check memory usage
docker stats myapp-container --no-stream

# Set soft limit (--memory-reservation)
docker run --memory=512m --memory-reservation=256m myapp:1.0
```

### Q9: How do you implement zero-downtime deployments?

```bash
# Method 1: Docker Compose with multiple replicas
docker compose up -d --scale web=2

# Method 2: Blue-Green deployment
# Deploy green version
docker run -d --name app-green -p 8081:8080 myapp:2.0
# Test green version
# Switch load balancer to green
# Remove blue version
docker rm -f app-blue

# Method 3: Docker Swarm rolling update
docker service update --image myapp:2.0 --update-parallelism 1 --update-delay 10s myservice

# Method 4: Use health checks for readiness
docker run -d --health-cmd 'curl -f http://localhost/health' \
    --health-interval=5s --health-retries=3 myapp:1.0
```

### Q10: How do you optimize Docker build times?

```bash
# 1. Order Dockerfile commands by change frequency
# 2. Use BuildKit
DOCKER_BUILDKIT=1 docker build .

# 3. Use cache mounts
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt

# 4. Use parallel builds in multi-stage
docker buildx build --target production .

# 5. Use remote cache
docker build --cache-from myregistry/myapp:cache -t myapp .

# 6. Check build time per layer
docker build --progress=plain .
```

---

## Command Quick Reference Table

| Task | Command |
|------|---------|
| Build image | `docker build -t app:1.0 .` |
| Run container | `docker run -d -p 8080:80 app:1.0` |
| View logs | `docker logs -f container` |
| Exec into container | `docker exec -it container sh` |
| Stop container | `docker stop container` |
| Remove container | `docker rm container` |
| Remove image | `docker rmi image:tag` |
| List containers | `docker ps -a` |
| List images | `docker images` |
| Cleanup system | `docker system prune -a` |
| View stats | `docker stats` |
| Inspect resource | `docker inspect resource` |
| Copy files | `docker cp container:/path ./local` |
| Create network | `docker network create name` |
| Create volume | `docker volume create name` |

---

## Environment Variables Quick Reference

```bash
# Essential Docker environment variables
export DOCKER_BUILDKIT=1           # Enable BuildKit
export COMPOSE_DOCKER_CLI_BUILD=1  # Use Docker CLI for compose builds
export DOCKER_SCAN_SUGGEST=false   # Disable scan suggestions
export DOCKER_CLI_HINTS=false      # Disable CLI hints
export DOCKER_HOST=tcp://...       # Remote Docker host
export DOCKER_TLS_VERIFY=1         # Enable TLS verification
export DOCKER_CERT_PATH=~/.docker  # TLS certificate path
```
