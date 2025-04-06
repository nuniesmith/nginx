###############################
# Nginx Dockerfile with 2-stage build
###############################
#
# OVERVIEW:
# This Dockerfile creates a multi-stage build for Nginx:
# - Stage 1 (Builder): Prepares configuration files and static content
# - Stage 2 (Runtime): Creates a lean runtime image with only necessary components
#
# USAGE:
# docker build -t nginx-honeybun:latest .
#
###############################

###############################
# Stage 1: Builder
###############################
FROM alpine:latest AS builder

# Build arguments
ARG CONFIG_PATH=./config/nginx
ARG HTML_PATH=./config/html

WORKDIR /build

# Install necessary tools for validation
RUN apk add --no-cache nginx

# Copy Nginx configuration files to builder
COPY ${CONFIG_PATH}/nginx.conf /build/nginx.conf
COPY ${CONFIG_PATH}/conf.d /build/conf.d
COPY ${CONFIG_PATH}/proxy_params_common.conf /build/proxy_params_common.conf
COPY ${CONFIG_PATH}/proxy_params_websocket.conf /build/proxy_params_websocket.conf

# Copy HTML content to builder
COPY ${HTML_PATH}/honeybun /build/html/honeybun

# Create a default index.html if none exists
RUN if [ ! -e /build/html/honeybun/index.html ]; then \
    mkdir -p /build/html/honeybun && \
    echo '<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>Welcome to Honeybun</h1><p>Site under construction</p></body></html>' > /build/html/honeybun/index.html; \
    fi

# Validate configuration syntax
RUN nginx -t -c /build/nginx.conf || (echo "Configuration invalid"; exit 1)
RUN echo "Configuration validation complete"

###############################
# Stage 2: Runtime
###############################
FROM nginx:stable-alpine AS runtime

# Runtime arguments with defaults
ARG SERVICE_PORT=80
ARG SERVICE_NAME="nginx-honeybun"
ARG APP_VERSION=1.0.0
ARG APP_ENV=production
ARG ENABLE_HEALTHCHECK=true

# Set runtime environment variables
ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_PORT=${SERVICE_PORT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV} \
    ENABLE_HEALTHCHECK=${ENABLE_HEALTHCHECK}

# Create necessary directories with proper permissions
RUN mkdir -p /var/www/html/honeybun && \
    chown -R nginx:nginx /var/www/html && \
    chmod -R 755 /var/www/html

# Copy Nginx configuration from builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/conf.d /etc/nginx/conf.d/
COPY --from=builder /build/proxy_params_common.conf /etc/nginx/
COPY --from=builder /build/proxy_params_websocket.conf /etc/nginx/

# Copy HTML content from builder stage with correct ownership
COPY --from=builder --chown=nginx:nginx /build/html/honeybun /var/www/html/honeybun

# Set proper permissions for all files and directories
RUN chown -R nginx:nginx /var/www/html && \
    chmod -R 755 /var/www/html && \
    find /var/www/html -type d -exec chmod 755 {} \; && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    # Make Nginx config files readable by the Nginx process
    chmod -R 644 /etc/nginx/conf.d/*.conf && \
    chmod 644 /etc/nginx/nginx.conf && \
    chmod 644 /etc/nginx/proxy_params_common.conf && \
    chmod 644 /etc/nginx/proxy_params_websocket.conf && \
    # Verify configuration is valid
    nginx -t

# Add a special script for healthcheck
RUN echo '#!/bin/sh\nif [ "${ENABLE_HEALTHCHECK}" != "true" ]; then exit 0; fi\nnginx -t >/dev/null 2>&1 || exit 1\ncurl -s -f http://localhost:${SERVICE_PORT}/ >/dev/null 2>&1 || exit 1\nexit 0' > /usr/local/bin/healthcheck.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# Label the image with metadata
ARG BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
LABEL org.opencontainers.image.title="${SERVICE_NAME}" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="Nginx container for ${SERVICE_NAME} service" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.environment="${APP_ENV}"

# Expose the service port
EXPOSE ${SERVICE_PORT}

# Health Check
HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Default command - runs nginx in foreground
CMD ["nginx", "-g", "daemon off;"]