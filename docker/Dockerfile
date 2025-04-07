###############################
# Stage 1: Config Check & Build
###############################
FROM nginx:latest AS builder

# Install necessary tools for config checking
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create test directory for verifying config
WORKDIR /build
COPY ./config/nginx/nginx.conf /build/nginx.conf
COPY ./config/nginx/maps.conf /build/maps.conf
COPY ./config/nginx/mime.types.conf /build/mime.types.conf
COPY ./config/nginx/conf.d /build/conf.d
COPY ./config/nginx/includes /build/includes

# Copy website content for testing
COPY ./config/html/honeybun /build/html/honeybun
COPY ./config/html/fks /build/html/fks

# Copy mime.types.conf and maps.conf to the exact locations nginx.conf is looking for
COPY ./config/nginx/mime.types.conf /etc/nginx/mime.types.conf
COPY ./config/nginx/maps.conf /etc/nginx/maps.conf

# Test nginx config
RUN nginx -c /build/nginx.conf -t

###############################
# Stage 2: Runtime
###############################
FROM nginx:latest AS runtime

# Build arguments
ARG SERVICE_PORT=80
ARG SERVICE_NAME="nginx-web"
ARG APP_VERSION=1.0.0
ARG APP_ENV=production

# Set runtime environment variables
ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_PORT=${SERVICE_PORT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV}

# Install necessary tools with proper cleanup
RUN apt-get update && apt-get install -y \
    curl \
    inotify-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated non-root user for Nginx
RUN addgroup --system --gid 1001 nginx-app && \
    adduser --system --disabled-login --ingroup nginx-app --no-create-home --home /nonexistent --gecos "nginx-app user" --shell /bin/false --uid 1001 nginx-app

# Create directory structure with proper permissions
RUN mkdir -p /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/includes \
    /usr/share/nginx/html/health \
    /usr/share/nginx/html/honeybun.local/health \
    /usr/share/nginx/html/fks.local/health \
    /usr/share/nginx/html/fks.local/metrics/health \
    /usr/share/nginx/html/fks.local/db/health \
    /config/html/honeybun \
    /config/html/fks \
    /config/html/metrics \
    /config/html/db

# Copy configurations from the builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/maps.conf /etc/nginx/maps.conf
COPY --from=builder /build/conf.d/ /etc/nginx/conf.d/
COPY --from=builder /build/includes/ /etc/nginx/includes/
COPY --from=builder /build/mime.types.conf /etc/nginx/mime.types.conf

# Copy website content from builder stage
COPY --from=builder /build/html/honeybun/ /usr/share/nginx/html/honeybun.local/
COPY --from=builder /build/html/fks/ /usr/share/nginx/html/fks.local/

# Create simple health check pages for each domain and root
RUN echo "OK" > /usr/share/nginx/html/honeybun.local/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/metrics/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/db/health/index.html

# Create symbolic links to keep original directory structure
RUN ln -sf /usr/share/nginx/html/honeybun.local /config/html/honeybun && \
    ln -sf /usr/share/nginx/html/fks.local /config/html/fks

# Set proper permissions for Nginx directories
RUN touch /var/run/nginx.pid && \
    chown -R nginx-app:nginx-app /var/run/nginx.pid /var/cache/nginx /var/log/nginx /config /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html /etc/nginx /config

# Add healthcheck that verifies both domains
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl --fail -H "Host: localhost" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: honeybun.local" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: fks.local" http://localhost:${SERVICE_PORT}/health || exit 1

# Label the image with metadata
LABEL org.opencontainers.image.title="${SERVICE_NAME}" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="Nginx web server with custom configuration" \
      org.opencontainers.image.created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      org.opencontainers.image.environment="${APP_ENV}"

# Expose the service port
EXPOSE ${SERVICE_PORT}

# Run Nginx in the foreground (so Docker can track the process)
CMD ["nginx", "-g", "daemon off;"]