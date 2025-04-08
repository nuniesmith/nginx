###############################
# Stage 1: Build Nginx from source
###############################
FROM alpine:latest AS builder

# Nginx version
ARG NGINX_VERSION=1.26.0
ARG NGINX_GPG_KEYS=13C82A63B603576156E30A4EA0EA981B66B0D967

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
    gnupg \
    libxslt-dev \
    gd-dev \
    perl-dev

# Download and verify Nginx source
WORKDIR /src
RUN wget "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    wget "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc" && \
    mkdir -p /root/.gnupg && \
    gpg --keyserver keyserver.ubuntu.com --recv-keys "$NGINX_GPG_KEYS" && \
    gpg --verify nginx-${NGINX_VERSION}.tar.gz.asc && \
    tar -zxvf nginx-${NGINX_VERSION}.tar.gz

# Configure and compile Nginx with desired modules
WORKDIR /src/nginx-${NGINX_VERSION}
RUN ./configure \
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

# Set runtime environment variables
ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_PORT=${SERVICE_PORT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV}

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    inotify-tools \
    pcre \
    libssl3 \
    libgcc

# Create a dedicated non-root user for Nginx
RUN addgroup -S nginx && \
    adduser -S -D -H -h /nonexistent -s /sbin/nologin -G nginx -u 101 nginx

# Create required directories with correct permissions for read-only filesystem
RUN mkdir -p /var/cache/nginx \
    /var/log/nginx \
    /etc/nginx/includes \
    /etc/nginx/conf.d \
    /run/nginx \
    /usr/share/nginx/html/health \
    /usr/share/nginx/html/honeybun.local/health \
    /usr/share/nginx/html/fks.local/health \
    /usr/share/nginx/html/fks.local/metrics/health \
    /usr/share/nginx/html/fks.local/db/health \
    /config/html/honeybun \
    /config/html/fks \
    /config/html/metrics \
    /config/html/db \
    /tmp/nginx

# Copy compiled Nginx binary and libraries from builder
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx/modules/ /etc/nginx/modules/
COPY --from=builder /etc/nginx/mime.types /etc/nginx/mime.types

# Copy configurations from the builder stage
COPY --from=builder /build/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /build/maps.conf /etc/nginx/maps.conf
COPY --from=builder /build/conf.d/ /etc/nginx/conf.d/
COPY --from=builder /build/includes/ /etc/nginx/includes/
COPY --from=builder /build/mime.types.conf /etc/nginx/mime.types.conf

# Create empty default.conf if it doesn't exist
RUN touch /etc/nginx/conf.d/default.conf

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

# Configure for read-only filesystem with writable areas
RUN chown -R nginx-app:nginx-app /var/cache/nginx /var/log/nginx /run/nginx /tmp/nginx && \
    chmod -R 755 /usr/share/nginx/html /etc/nginx /config

# Add healthcheck that verifies both domains
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl --fail -H "Host: localhost" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: honeybun.local" http://localhost:${SERVICE_PORT}/health && \
        curl --fail -H "Host: fks.local" http://localhost:${SERVICE_PORT}/health || exit 1

# Label the image with metadata
LABEL org.opencontainers.image.title="${SERVICE_NAME}" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="Custom Nginx web server compiled from source" \
      org.opencontainers.image.created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      org.opencontainers.image.environment="${APP_ENV}"

# Expose the service port
EXPOSE ${SERVICE_PORT}

# Run Nginx with configuration for read-only filesystem
CMD ["nginx", "-g", "daemon off; error_log /dev/stderr; pid /run/nginx/nginx.pid; load_module modules/ngx_http_image_filter_module.so;"]