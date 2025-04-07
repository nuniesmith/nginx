#!/bin/bash
set -e

echo "Starting Nginx config watcher..."

# Function to test and reload nginx config
reload_nginx() {
    echo "Config change detected, testing configuration..."
    if nginx -t; then
        echo "Configuration test successful, reloading Nginx..."
        nginx -s reload
        echo "Nginx reloaded successfully at $(date)"
    else
        echo "Configuration test failed, keeping current configuration."
    fi
}

# Function to check if Nginx is running
check_nginx() {
    if ! pgrep -x "nginx" > /dev/null; then
        echo "Nginx is not running! Attempting to restart at $(date)"
        nginx -g "daemon off;" &
        NGINX_PID=$!
        echo "Nginx restarted with PID: $NGINX_PID"
    else
        echo "Heartbeat check: Nginx is running normally at $(date)"
    fi
}

# Function to handle signals
handle_exit() {
    echo "Received shutdown signal, stopping Nginx gracefully..."
    if [[ -n "$NGINX_PID" ]]; then
        kill -TERM "$NGINX_PID" || true
    fi
    nginx -s quit || true
    exit 0
}

# Setup signal traps
trap handle_exit SIGINT SIGTERM

# Start Nginx in the background
nginx -g "daemon off;" &
NGINX_PID=$!
echo "Nginx started with PID: $NGINX_PID"

# Setup heartbeat interval (in seconds)
HEARTBEAT_INTERVAL=300  # 5 minutes

echo "Watching for changes in /etc/nginx/ directory..."
echo "Heartbeat check will run every $HEARTBEAT_INTERVAL seconds"

# Start the heartbeat timer
LAST_HEARTBEAT=$(date +%s)

# Watch for changes in nginx config files
while true; do
    # Wait for file system events with a timeout
    if inotifywait -r -e modify,create,delete,move -t 60 /etc/nginx/; then
        # Only reload if config files changed
        reload_nginx
    fi
    
    # Check if it's time for a heartbeat
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - LAST_HEARTBEAT))
    
    if [ $ELAPSED -ge $HEARTBEAT_INTERVAL ]; then
        check_nginx
        LAST_HEARTBEAT=$CURRENT_TIME
    fi
    
    # Short sleep to prevent CPU spinning if inotifywait fails
    sleep 1
done