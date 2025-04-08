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

# Clone Nginx from GitHub
WORKDIR /src
RUN git clone https://github.com/nginx/nginx.git && \
    cd nginx && \
    git checkout release-1.26.0

# Create modules directory
RUN mkdir -p /usr/lib/nginx/modules

# Configure and compile Nginx with desired modules
WORKDIR /src/nginx
RUN ./auto/configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/tmp/nginx/nginx.pid \
    --lock-path=/tmp/nginx/nginx.lock \
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
    /tmp/nginx

# Create test directory
WORKDIR /build
COPY ./config/nginx/nginx.conf /build/nginx.conf
COPY ./config/nginx/maps.conf /build/maps.conf
COPY ./config/nginx/mime.types.conf /build/mime.types.conf
COPY ./config/nginx/includes /build/includes

# Copy website content for testing
COPY ./config/html/honeybun /build/html/honeybun
COPY ./config/html/fks /build/html/fks

# Copy mime.types.conf and maps.conf to the exact locations nginx.conf is looking for
COPY ./config/nginx/mime.types.conf /etc/nginx/mime.types.conf
COPY ./config/nginx/maps.conf /etc/nginx/maps.conf

# Create conf.d directory
RUN mkdir -p /build/conf.d

# Copy your conf files
COPY ./config/nginx/conf.d /build/conf.d

# Modify the nginx.conf to use the new PID path
RUN sed -i 's|pid /var/run/nginx.pid;|pid /tmp/nginx/nginx.pid;|' /build/nginx.conf

# Ensure the modules directory exists and has at least an empty file
RUN mkdir -p /usr/lib/nginx/modules && \
    touch /usr/lib/nginx/modules/.keep

###############################
# Stage 2: Runtime
###############################
FROM alpine:latest AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    pcre \
    libssl3 \
    libgcc

# Create required directories with correct permissions WHILE STILL ROOT
# Using 1777 (sticky bit) to ensure only owners can delete their files
RUN mkdir -p /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/includes \
    /etc/nginx/conf.d \
    /tmp/nginx \
    /usr/lib/nginx/modules \
    /usr/share/nginx/html/health \
    /usr/share/nginx/html/honeybun.local/health \
    /usr/share/nginx/html/fks.local/health && \
    chmod 1777 /var/cache/nginx /var/log/nginx /tmp/nginx && \
    # Ensure subdirectories also have correct permissions
    mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chmod 1777 /var/cache/nginx/client_temp \
               /var/cache/nginx/proxy_temp \
               /var/cache/nginx/fastcgi_temp \
               /var/cache/nginx/uwsgi_temp \
               /var/cache/nginx/scgi_temp

# Copy compiled Nginx binary and libraries from builder
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

# Copy modules directory from builder
COPY --from=builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/

# Copy configurations from the builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/maps.conf /etc/nginx/maps.conf
COPY --from=builder /build/conf.d/ /etc/nginx/conf.d/
COPY --from=builder /build/includes/ /etc/nginx/includes/
COPY --from=builder /build/mime.types.conf /etc/nginx/mime.types.conf
COPY --from=builder /etc/nginx/mime.types /etc/nginx/mime.types

# Copy website content from builder stage
COPY --from=builder /build/html/honeybun/ /usr/share/nginx/html/honeybun.local/
COPY --from=builder /build/html/fks/ /usr/share/nginx/html/fks.local/

# Create simple health check pages
RUN echo "OK" > /usr/share/nginx/html/honeybun.local/health/index.html && \
    echo "OK" > /usr/share/nginx/html/fks.local/health/index.html && \
    mkdir -p /usr/share/nginx/html/health && \
    echo "OK" > /usr/share/nginx/html/health/index.html

# Ensure HTML directories are writable
RUN chmod -R 777 /usr/share/nginx/html

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl --fail http://localhost/health || exit 1

# Setup entrypoint script that doesn't try to change permissions
COPY --chown=root:root <<-"EOF" /entrypoint.sh
#!/bin/sh
set -e

# Display all config files for debugging
echo "Nginx configuration files:"
ls -la /etc/nginx/conf.d/

# Fix any syntax issues in config files
echo "Fixing any syntax issues in configuration files..."
find /etc/nginx/conf.d -type f -name "*.conf" -exec sed -i 's/}#/}\n#/g' {} \;
find /etc/nginx/conf.d -type f -name "*.conf" -exec sed -i 's/server {/server {\n/g' {} \;
find /etc/nginx/conf.d -type f -name "*.conf" -exec sed -i 's/}/}\n/g' {} \;

# Test the configuration
echo "Testing Nginx configuration..."
nginx -t || { echo "Configuration test failed!"; find /etc/nginx/conf.d -type f -name "*.conf" -exec cat {} \; ; exit 1; }

# Start Nginx in foreground mode
echo "Starting nginx..."
exec nginx -g "daemon off;"
EOF

RUN chmod +x /entrypoint.sh

# Expose port 80
EXPOSE 80

# Run entrypoint script
ENTRYPOINT ["/entrypoint.sh"]