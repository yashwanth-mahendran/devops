# Docker Concepts & Examples

This folder contains Dockerfile examples for different application types and comprehensive documentation on Docker best practices and commands.

## 📁 Folder Structure

```
docker/
├── README.md                  # This file
├── BEST_PRACTICES.md          # Dockerfile best practices
├── DOCKER_COMMANDS.md         # Production & interview-based commands
├── nodejs/
│   └── Dockerfile             # Node.js application example
├── java/
│   └── Dockerfile             # Java/Spring Boot application example
└── fastapi/
    └── Dockerfile             # FastAPI (Python) application example
```

## 🚀 Quick Start

### Building Images

```bash
# Node.js application
cd nodejs && docker build -t nodejs-app:1.0 .

# Java application
cd java && docker build -t java-app:1.0 .

# FastAPI application
cd fastapi && docker build -t fastapi-app:1.0 .
```

### Running Containers

```bash
# Node.js
docker run -d -p 3000:3000 --name nodejs-container nodejs-app:1.0

# Java
docker run -d -p 8080:8080 --name java-container java-app:1.0

# FastAPI
docker run -d -p 8000:8000 --name fastapi-container fastapi-app:1.0
```

## 📚 Documentation

- [Dockerfile Best Practices](./BEST_PRACTICES.md)
- [Docker Commands Reference](./DOCKER_COMMANDS.md)

## 💡 Key Concepts Covered

1. **Multi-stage builds** - Reduce image size and attack surface
2. **Layer caching** - Optimize build times
3. **Security best practices** - Non-root users, minimal base images
4. **Health checks** - Container health monitoring
5. **Environment management** - Configuration via environment variables
6. **Networking** - Container communication
7. **Volume management** - Data persistence
