#!/bin/bash

set -e

# Configuration
REPO_URL=${REPO_URL:-"https://github.com/nuniesmith/nginx.git"}
BRANCH=${BRANCH:-"main"}
WATCH_INTERVAL=${WATCH_INTERVAL:-300}
NGINX_CONTAINER_NAME=${NGINX_CONTAINER_NAME:-"nginx"}
CONFIG_DIR=${CONFIG_DIR:-"/app/config"}

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Initial setup
if [ ! -d "$CONFIG_DIR/.git" ]; then
    log "Performing initial clone of $REPO_URL to $CONFIG_DIR"
    # If CONFIG_DIR exists but is not a git repo, we need to clear it
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
    fi
    git clone -b "$BRANCH" "$REPO_URL" "$CONFIG_DIR"
    CURRENT_COMMIT=$(cd "$CONFIG_DIR" && git rev-parse HEAD)
    log "Initial clone complete. Current commit: $CURRENT_COMMIT"
else
    log "Git repository already exists in $CONFIG_DIR"
    CURRENT_COMMIT=$(cd "$CONFIG_DIR" && git rev-parse HEAD)
    log "Current commit: $CURRENT_COMMIT"
fi

# Setup SSH keys if provided
if [ -n "$SSH_PRIVATE_KEY" ]; then
    log "Setting up SSH keys"
    mkdir -p /root/.ssh
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    ssh-keyscan github.com >> /root/.ssh/known_hosts
    
    # Configure git to use SSH
    cd "$CONFIG_DIR"
    REPO_SSH_URL=$(echo "$REPO_URL" | sed 's|https://github.com/|git@github.com:|')
    git remote set-url origin "$REPO_SSH_URL"
    log "SSH keys configured. Using SSH URL: $REPO_SSH_URL"
fi

# Continuous monitoring loop
log "Starting monitoring of $REPO_URL (branch: $BRANCH)"
log "Checking every $WATCH_INTERVAL seconds"

while true; do
    cd "$CONFIG_DIR"
    
    # Fetch latest changes
    log "Fetching latest changes from remote"
    git fetch origin "$BRANCH"
    
    # Get the latest commit hash
    REMOTE_COMMIT=$(git rev-parse origin/"$BRANCH")
    log "Remote commit: $REMOTE_COMMIT"
    log "Current commit: $CURRENT_COMMIT"
    
    # Check if there are changes
    if [ "$REMOTE_COMMIT" != "$CURRENT_COMMIT" ]; then
        log "Changes detected, pulling latest code"
        
        # Pull changes
        git pull origin "$BRANCH"
        CURRENT_COMMIT="$REMOTE_COMMIT"
        
        # Restart Nginx container
        log "Restarting Nginx container: $NGINX_CONTAINER_NAME"
        if docker restart "$NGINX_CONTAINER_NAME"; then
            log "Nginx container restarted successfully"
        else
            log "Failed to restart Nginx container"
        fi
    else
        log "No changes detected"
    fi
    
    # Wait for next check
    log "Sleeping for $WATCH_INTERVAL seconds"
    sleep "$WATCH_INTERVAL"
done