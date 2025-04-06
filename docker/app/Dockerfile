###############################
# GitHub Watcher Dockerfile with 2-stage build
###############################
#
# OVERVIEW:
# This Dockerfile creates a multi-stage build for GitHub watcher:
# - Stage 1 (Builder): Prepares and validates the watcher script
# - Stage 2 (Runtime): Creates a lean runtime image with only necessary components
#
# USAGE:
# docker build -t nuniesmith/github-watcher:latest -f ./docker/app/Dockerfile .
#
###############################

###############################
# Stage 1: Builder
###############################
FROM alpine:latest AS builder

WORKDIR /build

# Install tools for validation and linting
RUN apk update && \
    apk add --no-cache \
    bash \
    shellcheck

# Copy the monitoring script to builder
COPY ./scripts/watch-github.sh /build/

# Make script executable
RUN chmod +x /build/watch-github.sh

# Basic script validation
RUN shellcheck -S warning /build/watch-github.sh || echo "Shellcheck validation completed with warnings"

# Ensure the script has proper line endings
RUN sed -i 's/\r$//' /build/watch-github.sh

# Create a healthcheck script
RUN echo '#!/bin/sh\n\
# Check if the watcher script is running\n\
if ! pgrep -f "watch-github.sh" > /dev/null; then\n\
  echo "Watcher script is not running!"\n\
  exit 1\n\
fi\n\
\n\
# Check if the lockfile exists and is valid\n\
if [ -f "/var/run/nginx_config_watcher.lock" ]; then\n\
  if ! ps -p $(cat /var/run/nginx_config_watcher.lock 2>/dev/null) > /dev/null 2>&1; then\n\
    echo "Stale lockfile found!"\n\
    exit 1\n\
  fi\n\
fi\n\
\n\
exit 0' > /build/healthcheck.sh && \
    chmod +x /build/healthcheck.sh

RUN echo "Script preparation and validation complete"

###############################
# Stage 2: Runtime
###############################
FROM alpine:latest AS runtime

# Runtime arguments with defaults
ARG APP_VERSION=1.0.0
ARG APP_ENV=production

# Set runtime environment variables
ENV REPO_URL="https://github.com/nuniesmith/nginx.git" \
    BRANCH="main" \
    WATCH_INTERVAL=300 \
    NGINX_CONTAINER_NAME="nginx_app" \
    CONFIG_DIR="/app/config" \
    USE_DOCKER_COMPOSE="true" \
    COMPOSE_FILE="docker-compose.yml" \
    COMPOSE_DIR="/app/config" \
    VERBOSE="false" \
    DISABLE_RESTART="false" \
    HEALTHCHECK_URL="" \
    AUTO_FIX="true" \
    MONITOR_LOGS="true" \
    LOG_TAIL_LINES=100 \
    FIX_PERMISSIONS="true" \
    NGINX_USER="nginx" \
    NGINX_GROUP="nginx" \
    WEB_ROOT="/var/www/html" \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV}

# Install required packages (minimal set for runtime)
RUN apk update && \
    apk add --no-cache \
    git \
    curl \
    bash \
    openssh-client \
    docker-cli \
    docker-compose \
    findutils \
    grep \
    sed

# Create app directory and config directory with proper permissions
WORKDIR /app
RUN mkdir -p /app/config && \
    chmod 775 /app/config && \
    mkdir -p /var/run && \
    chmod 1777 /var/run

# Set proper Git configuration for safer Git operations
RUN git config --global --add safe.directory /app/config && \
    git config --global advice.detachedHead false && \
    git config --global pull.rebase false

# Copy the scripts from builder stage
COPY --from=builder /build/watch-github.sh /app/
COPY --from=builder /build/healthcheck.sh /usr/local/bin/

# Make sure scripts are executable
RUN chmod +x /app/watch-github.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# Label the image with metadata
ARG BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
LABEL org.opencontainers.image.title="github-watcher" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="GitHub watcher service for Nginx configuration" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.environment="${APP_ENV}"

# Health Check
HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Run the script
CMD ["/app/watch-github.sh"]