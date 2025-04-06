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

# Copy Nginx configuration files to builder
COPY ${CONFIG_PATH}/nginx.conf /build/nginx.conf
COPY ${CONFIG_PATH}/conf.d /build/conf.d
COPY ${CONFIG_PATH}/proxy_params_common.conf /build/proxy_params_common.conf
COPY ${CONFIG_PATH}/proxy_params_websocket.conf /build/proxy_params_websocket.conf

# Copy HTML content to builder
COPY ${HTML_PATH}/honeybun /build/html/honeybun

# Validate configuration syntax if needed
# This step could be expanded if you want to perform linting or validation
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

# Create necessary directories
RUN mkdir -p /var/www/html/honeybun

# Copy Nginx configuration from builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/conf.d /etc/nginx/conf.d/
COPY --from=builder /build/proxy_params_common.conf /etc/nginx/
COPY --from=builder /build/proxy_params_websocket.conf /etc/nginx/

# Copy HTML content from builder stage
COPY --from=builder /build/html/honeybun /var/www/html/honeybun

# Set proper permissions
RUN chown -R nginx:nginx /var/www/html && \
    chmod -R 755 /var/www/html && \
    # Verify configuration is valid
    nginx -t

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
    CMD if [ "${ENABLE_HEALTHCHECK}" = "true" ]; else exit 0; fi

# Default command - runs nginx in foreground
CMD ["nginx", "-g", "daemon off;"]