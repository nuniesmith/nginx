###############################
# Stage 1: Build Nginx from source using GitHub
###############################
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    curl \
    git \
    libxslt-dev \
    gd-dev \
    perl-dev \
    autoconf \
    automake

# Create nginx user and group in builder stage
RUN addgroup -S nginx && \
    adduser -S -D -H -h /nonexistent -s /sbin/nologin -G nginx -u 101 nginx

# Clone Nginx from GitHub
WORKDIR /src
RUN git clone https://github.com/nginx/nginx.git && \
    cd nginx && \
    git checkout release-1.26.0

# Configure and compile Nginx with desired modules
WORKDIR /src/nginx
RUN ./auto/configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module && \
    make -j$(nproc) && \
    make install

# Create required directories for testing
RUN mkdir -p /var/cache/nginx \
    /var/log/nginx \
    /run/nginx \
    /var/run \
    /tmp/nginx && \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx /run/nginx /var/run /tmp/nginx

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

# Create empty default.conf if it doesn't exist
RUN mkdir -p /build/conf.d && \
    touch /build/conf.d/default.conf

# Verify the modules directory exists (create if not)
RUN mkdir -p /usr/lib/nginx/modules

# Modify the nginx.conf to use the new PID path
RUN sed -i 's|pid /var/run/nginx.pid;|pid /var/run/nginx.pid;|' /build/nginx.conf

# Test nginx config
RUN nginx -c /build/nginx.conf -t

###############################
# Stage 2: Runtime
###############################
FROM alpine:latest AS runtime

# Build arguments
ARG SERVICE_PORT=80
ARG SERVICE_NAME="nginx-web"
ARG APP_VERSION=1.0.0
ARG APP_ENV=production
ARG RUN_AS_NON_ROOT=false

# Set runtime environment variables
ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_PORT=${SERVICE_PORT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV} \
    RUN_AS_NON_ROOT=${RUN_AS_NON_ROOT}

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    inotify-tools \
    pcre \
    libssl3 \
    libgcc \
    su-exec

# Create dedicated non-root users for Nginx
RUN addgroup -S nginx && \
    adduser -S -D -H -h /nonexistent -s /sbin/nologin -G nginx -u 101 nginx && \
    addgroup -S nginx-app && \
    adduser -S -D -H -h /nonexistent -s /sbin/nologin -G nginx-app -u 1001 nginx-app

# Create required directories with correct permissions
RUN mkdir -p /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/includes \
    /etc/nginx/conf.d \
    /run/nginx \
    /var/run \
    /usr/lib/nginx/modules \
    /usr/share/nginx/html/health \
    /usr/share/nginx/html/honeybun.local/health \
    /usr/share/nginx/html/fks.local/health \
    /usr/share/nginx/html/fks.local/metrics/health \
    /usr/share/nginx/html/fks.local/db/health \
    /tmp/nginx

# Copy compiled Nginx binary and libraries from builder
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

# Copy modules from the correct location (if they exist)
COPY --from=builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/

# Copy configurations from the builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/maps.conf /etc/nginx/maps.conf
COPY --from=builder /build/conf.d/ /etc/nginx/conf.d/
COPY --from=builder /build/includes/ /etc/nginx/includes/
COPY --from=builder /build/mime.types.conf /etc/nginx/mime.types.conf
COPY --from=builder /etc/nginx/mime.types /etc/nginx/mime.types

# Create a simple server block for honeybun.local
RUN echo 'server {\n\
    listen 80;\n\
    server_name honeybun.local;\n\
    root /usr/share/nginx/html/honeybun.local;\n\
    index index.html;\n\
    access_log /var/log/nginx/honeybun.access.log;\n\
    error_log /var/log/nginx/honeybun.error.log;\n\
\n\
    location = /health {\n\
        try_files /health/index.html =200;\n\
        add_header Content-Type text/html;\n\
        add_header Cache-Control "no-cache, no-store, must-revalidate";\n\
        add_header Pragma "no-cache";\n\
    }\n\
\n\
    location / {\n\
        try_files $uri $uri/ /index.html =404;\n\
    }\n\
}' > /etc/nginx/conf.d/honeybun.conf

# Copy website content from builder stage
COPY --from=builder /build/html/honeybun/ /usr/share/nginx/html/honeybun.local/
COPY --from=builder /build/html/fks/ /usr/share/nginx/html/fks.local/

# Create simple health check pages for each domain and root
RUN echo "OK" > /usr/share/nginx/html/honeybun.local/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/metrics/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/db/health/index.html && \
    mkdir -p /usr/share/nginx/html/health && \
    echo "OK" > /usr/share/nginx/html/health/index.html

# Setup writable temporary directories for read-only filesystem
VOLUME ["/var/cache/nginx", "/var/log/nginx", "/run/nginx", "/tmp/nginx"]

# Pre-create the PID directory and make it writable by nginx-app
RUN mkdir -p /var/run && \
    touch /var/run/nginx.pid && \
    chown -R nginx-app:nginx-app /var/run/nginx.pid /var/run && \
    chmod 777 /var/run

# Configure file permissions correctly
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx /run/nginx /tmp/nginx && \
    chown -R nginx-app:nginx-app /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html /etc/nginx && \
    chmod 777 /run/nginx /var/run

# Add healthcheck that verifies all domains
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl --fail -H "Host: localhost" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: honeybun.local" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: fks.local" http://localhost:${SERVICE_PORT}/health || exit 1

# Setup entrypoint script to handle permissions and startup
COPY --chown=root:root <<-"EOF" /entrypoint.sh
#!/bin/sh
set -e

# If running as root, we can fix permissions, otherwise skip permission fixing
if [ "$(id -u)" = "0" ]; then
    # Create the PID directory with proper permissions
    mkdir -p /var/run
    mkdir -p /run/nginx
    touch /var/run/nginx.pid
    chown -R nginx-app:nginx-app /var/run/nginx.pid /var/run
    chmod 777 /run/nginx /var/run
    
    # If RUN_AS_NON_ROOT is true, switch to nginx-app user
    if [ "${RUN_AS_NON_ROOT}" = "true" ]; then
        echo "Switching to non-root nginx-app user..."
        exec su-exec nginx-app nginx -g "daemon off;"
    else
        echo "Starting nginx as root..."
        exec nginx -g "daemon off;"
    fi
else
    # Running as non-root already
    echo "Starting nginx as $(id -un)..."
    exec nginx -g "daemon off;"
fi
EOF

RUN chmod +x /entrypoint.sh

# Expose the service port
EXPOSE ${SERVICE_PORT}

# Run entrypoint script
ENTRYPOINT ["/entrypoint.sh"]