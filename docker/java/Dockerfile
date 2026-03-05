# ============================================
# Java/Spring Boot Dockerfile - Production Ready
# ============================================
# This Dockerfile demonstrates best practices for
# containerizing Java applications with multi-stage builds

# ============================================
# STAGE 1: Build Stage with Maven
# ============================================
FROM maven:3.9-eclipse-temurin-21-alpine AS builder

# Set working directory
WORKDIR /app

# Copy pom.xml first (layer caching optimization)
COPY pom.xml .

# Download dependencies (cached unless pom.xml changes)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests -B

# Extract layers for Spring Boot layered jar (optional optimization)
RUN java -Djarmode=layertools -jar target/*.jar extract

# ============================================
# STAGE 2: Production Stage
# ============================================
FROM eclipse-temurin:21-jre-alpine AS production

# Security - Add labels for container metadata
LABEL maintainer="devops@example.com"
LABEL version="1.0"
LABEL description="Production Java Spring Boot Application"

# Security - Create non-root user
RUN addgroup -g 1001 -S spring && \
    adduser -S spring -u 1001 -G spring

# Set working directory
WORKDIR /app

# JVM tuning for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:InitialRAMPercentage=50.0 \
               -XX:+UseG1GC \
               -XX:+HeapDumpOnOutOfMemoryError \
               -XX:HeapDumpPath=/app/logs" \
    SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=production

# Create logs directory
RUN mkdir -p /app/logs && chown -R spring:spring /app

# Copy Spring Boot layered jar (optimized for Docker layer caching)
COPY --from=builder --chown=spring:spring /app/dependencies/ ./
COPY --from=builder --chown=spring:spring /app/spring-boot-loader/ ./
COPY --from=builder --chown=spring:spring /app/snapshot-dependencies/ ./
COPY --from=builder --chown=spring:spring /app/application/ ./

# Switch to non-root user
USER spring

# Expose application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Start the application with JVM options
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]

# ============================================
# ALTERNATIVE: Simple JAR approach (without layered jar)
# ============================================
# FROM eclipse-temurin:21-jre-alpine AS simple
# WORKDIR /app
# COPY --from=builder /app/target/*.jar app.jar
# RUN addgroup -g 1001 -S spring && adduser -S spring -u 1001 -G spring
# USER spring
# EXPOSE 8080
# ENTRYPOINT ["java", "-jar", "app.jar"]

# ============================================
# ALTERNATIVE: With Gradle Build
# ============================================
# FROM gradle:8-jdk21-alpine AS gradle-builder
# WORKDIR /app
# COPY build.gradle settings.gradle ./
# RUN gradle dependencies --no-daemon
# COPY src ./src
# RUN gradle build -x test --no-daemon
