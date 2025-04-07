###############################
# Stage 1: Builder
###############################
FROM node:latest AS builder

WORKDIR /build

# Copy HTML and static assets
#COPY ./config/html /build/html

# If you need to process your HTML/CSS/JS files, you can do it here
# For example, using a simple npm package to minify HTML files:
# RUN npm install -g html-minifier && \
#     find /build/html -name "*.html" -exec html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype {} -o {} \;

# Copy nginx config files to verify them in the build stage
#COPY ./config/nginx /build/nginx

# Optionally verify nginx config
FROM nginx:latest AS config-check
#COPY --from=builder /build/nginx/nginx.conf /etc/nginx/nginx.conf
#COPY --from=builder /build/nginx/conf.d /etc/nginx/conf.d
#RUN mkdir -p /etc/nginx/includes
#COPY --from=builder /build/nginx/includes /etc/nginx/includes
RUN nginx -t

###############################
# Stage 2: Runtime
###############################
FROM nginx:latest AS runtime

# Build arguments
ARG NGINX_VERSION=latest
ARG SERVICE_PORT=80
ARG SERVICE_NAME="nginx-web"
ARG APP_VERSION=1.0.0
ARG APP_ENV=production

# Set runtime environment variables
ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_PORT=${SERVICE_PORT} \
    APP_VERSION=${APP_VERSION} \
    APP_ENV=${APP_ENV}

# Create a dedicated non-root user for Nginx
RUN addgroup --system --gid 1001 nginx-app && \
    adduser --system --disabled-login --ingroup nginx-app --no-create-home --home /nonexistent --gecos "nginx-app user" --shell /bin/false --uid 1001 nginx-app

# Create necessary directories with proper permissions
RUN mkdir -p /var/cache/nginx /var/log/nginx /etc/nginx/includes && \
    chown -R nginx-app:nginx-app /var/cache/nginx /var/log/nginx

# Copy the HTML files from builder stage
#COPY --from=builder --chown=nginx-app:nginx-app /build/html /usr/share/nginx/html

# Copy the Nginx configuration files from builder stage
#COPY --from=builder --chown=nginx-app:nginx-app /build/nginx/nginx.conf /etc/nginx/nginx.conf
#COPY --from=builder --chown=nginx-app:nginx-app /build/nginx/conf.d /etc/nginx/conf.d
#COPY --from=builder --chown=nginx-app:nginx-app /build/nginx/includes /etc/nginx/includes

# Set proper permissions for Nginx directories
RUN chmod -R 755 /usr/share/nginx/html && \
    chmod -R 755 /etc/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx-app:nginx-app /var/run/nginx.pid

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl --fail http://localhost:${SERVICE_PORT}/health || exit 1

# Label the image with metadata
LABEL org.opencontainers.image.title="${SERVICE_NAME}" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="Nginx web server with custom configuration" \
      org.opencontainers.image.created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      org.opencontainers.image.environment="${APP_ENV}"

# Expose the service port
EXPOSE ${SERVICE_PORT}

# Use a non-root user to run Nginx
USER nginx-app

# Default command
CMD ["nginx", "-g", "daemon off;"]