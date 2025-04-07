#!/bin/sh
# Nginx Healthcheck Script
# This script performs various checks to ensure the Nginx service is healthy
# It can be disabled by setting ENABLE_HEALTHCHECK=false

# Define log formatting function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Exit cleanly if healthchecks are disabled
if [ "${ENABLE_HEALTHCHECK}" != "true" ]; then 
  exit 0
fi

# Check 1: Verify nginx process is running
if ! pgrep -x "nginx" > /dev/null; then
  log "ERROR: Nginx process is not running"
  exit 1
fi

# Check 2: Verify nginx master process is running as root (expected behavior)
if ! ps aux | grep "nginx: master process" | grep -v grep > /dev/null; then
  log "ERROR: Nginx master process not running"
  exit 1
fi

# Check 3: Verify nginx worker processes are running as nginx user
if ! ps aux | grep "nginx: worker process" | grep nginx | grep -v grep > /dev/null; then
  log "ERROR: Nginx worker processes not running correctly"
  exit 1
fi

# Check 4: Verify nginx configuration is valid
if ! nginx -t >/dev/null 2>&1; then
  log "ERROR: Nginx configuration is invalid"
  exit 1
fi

# Check 5: Verify nginx can serve content
# Use retry logic in case nginx is still starting up
MAX_RETRY=3
RETRY_COUNT=0
CURL_TIMEOUT=3

while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
  if curl -s -f -m $CURL_TIMEOUT -o /dev/null http://localhost:${SERVICE_PORT:-80}/; then
    # Success
    exit 0
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  
  if [ $RETRY_COUNT -lt $MAX_RETRY ]; then
    log "WARNING: Nginx not responding on port ${SERVICE_PORT:-80}, retry $RETRY_COUNT/$MAX_RETRY"
    sleep 1
  fi
done

# If we got here, all retries failed
log "ERROR: Nginx is not responding on port ${SERVICE_PORT:-80} after $MAX_RETRY attempts"
exit 1