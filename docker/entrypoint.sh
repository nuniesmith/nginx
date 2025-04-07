#!/bin/sh
set -e

# Define a log function for consistent logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Define an error function that logs and exits
error() {
  log "[ERROR] $1"
  exit 1
}

# Define a warning function
warn() {
  log "[WARNING] $1"
}

# Print startup message
log "Starting Nginx service"
log "Environment: $APP_ENV"
log "Service: $SERVICE_NAME (v$APP_VERSION)"

# Validate essential environment variables with improved error handling
if [ -z "$SERVICE_PORT" ]; then
  warn "SERVICE_PORT not set, using default: 80"
  export SERVICE_PORT="80"
fi

if [ -z "$SERVICE_NAME" ]; then
  warn "SERVICE_NAME not set, using default: nginx-honeybun"
  export SERVICE_NAME="nginx-honeybun"
fi

# Check for custom configurations to apply
if [ "$ENABLE_GZIP" = "true" ]; then
  log "Enabling GZIP compression"
  sed -i 's/gzip off;/gzip on;/' /etc/nginx/nginx.conf || error "Failed to enable GZIP"
fi

if [ "$ENABLE_HTTPS_REDIRECT" = "true" ]; then
  log "Enabling HTTP to HTTPS redirects"
  # Create or modify server block for redirection
  if ! grep -q "return 301 https" /etc/nginx/conf.d/default.conf 2>/dev/null; then
    cat > /etc/nginx/conf.d/https-redirect.conf << EOF || error "Failed to create HTTPS redirect config"
server {
  listen 80;
  server_name _;
  location / {
    return 301 https://\$host\$request_uri;
  }
}
EOF
  fi
fi

# Set up web root directory if it doesn't exist
if [ ! -d "/var/www/html/honeybun" ]; then
  log "Creating web root directory structure"
  mkdir -p /var/www/html/honeybun || error "Failed to create web root directory"
fi

# Create a default index.html if it doesn't exist
if [ ! -f "/var/www/html/honeybun/index.html" ]; then
  log "Creating default index.html"
  cat > /var/www/html/honeybun/index.html << EOF || error "Failed to create default index.html"
<!DOCTYPE html>
<html>
<head>
  <title>Welcome to $SERVICE_NAME</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 800px;
      margin: 0 auto;
      padding: 20px;
    }
    h1 {
      color: #0066cc;
    }
  </style>
</head>
<body>
  <h1>Welcome to $SERVICE_NAME</h1>
  <p>This is the default page. Replace this with your content.</p>
  <p><small>Server version: $APP_VERSION | Environment: $APP_ENV</small></p>
</body>
</html>
EOF
fi

# Ensure proper file permissions
log "Setting correct file permissions"
chown -R nginx:nginx /var/www/html || warn "Failed to set ownership for web root"
chmod -R 755 /var/www/html || warn "Failed to set permissions for web root"
find /var/www/html -type d -exec chmod 755 {} \; || warn "Failed to set directory permissions"
find /var/www/html -type f -exec chmod 644 {} \; || warn "Failed to set file permissions"

# Make sure Nginx config files are readable
chmod -R 644 /etc/nginx/conf.d/*.conf || warn "Failed to set permissions for config files"
chmod 644 /etc/nginx/nginx.conf || warn "Failed to set permissions for nginx.conf"

# Check for SSL certificates if HTTPS is enabled
if [ "$ENABLE_HTTPS_REDIRECT" = "true" ]; then
  if [ ! -d "/etc/nginx/ssl" ] || [ ! "$(ls -A /etc/nginx/ssl)" ]; then
    warn "HTTPS redirect is enabled but no SSL certificates found in /etc/nginx/ssl"
  fi
fi

# Test Nginx configuration
log "Testing Nginx configuration"
nginx -t || error "Nginx configuration is invalid"

# Start Nginx
log "Nginx service is starting..."
exec nginx -g "daemon off;"