# ============================================
# Node.js Dockerfile - Production Ready
# ============================================
# This Dockerfile demonstrates best practices for
# containerizing Node.js applications

# ============================================
# STAGE 1: Build Stage
# ============================================
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files first (layer caching optimization)
COPY package*.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm ci --only=production=false

# Copy source code
COPY . .

# Build the application (TypeScript compilation, bundling, etc.)
RUN npm run build

# Prune dev dependencies after build
RUN npm prune --production

# ============================================
# STAGE 2: Production Stage
# ============================================
FROM node:20-alpine AS production

# Security - Add labels for container metadata
LABEL maintainer="devops@example.com"
LABEL version="1.0"
LABEL description="Production Node.js Application"

# Security - Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000

# Copy only necessary files from builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./

# Switch to non-root user
USER nodejs

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "dist/index.js"]

# ============================================
# ALTERNATIVE: Development Dockerfile
# ============================================
# FROM node:20-alpine AS development
# WORKDIR /app
# COPY package*.json ./
# RUN npm install
# COPY . .
# EXPOSE 3000
# CMD ["npm", "run", "dev"]
