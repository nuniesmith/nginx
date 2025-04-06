#!/bin/bash

# Exit on any error
set -e

# Configuration with defaults
REPO_URL=${REPO_URL:-"https://github.com/nuniesmith/nginx.git"}
BRANCH=${BRANCH:-"main"}
WATCH_INTERVAL=${WATCH_INTERVAL:-300}
NGINX_CONTAINER_NAME=${NGINX_CONTAINER_NAME:-"nginx"}
CONFIG_DIR=${CONFIG_DIR:-"/app/config"}
LOCKFILE="/var/run/nginx_config_watcher.lock"

# Function to log with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function for cleanup
cleanup() {
  log "Received shutdown signal, exiting gracefully"
  [ -f "$LOCKFILE" ] && rm -f "$LOCKFILE"
  exit 0
}

# Setup trap for signals
trap cleanup SIGINT SIGTERM EXIT

# Check for running instance
if [ -e "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  log "ERROR: Script is already running with PID $(cat "$LOCKFILE")"
  exit 1
fi
echo $$ > "$LOCKFILE"

# Check for Docker
if ! command -v docker >/dev/null 2>&1; then
  log "ERROR: Docker is not installed or not in PATH"
  exit 1
fi

# Initial setup
if [ ! -d "$CONFIG_DIR/.git" ]; then
  log "Performing initial clone of $REPO_URL to $CONFIG_DIR"
  # If CONFIG_DIR exists but is not a git repo, we need to clear it
  if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
  fi
  
  if ! git clone -b "$BRANCH" "$REPO_URL" "$CONFIG_DIR"; then
    log "ERROR: Failed to clone repository"
    exit 1
  fi
  
  CURRENT_COMMIT=$(cd "$CONFIG_DIR" && git rev-parse HEAD)
  log "Initial clone complete. Current commit: $CURRENT_COMMIT"
else
  log "Git repository already exists in $CONFIG_DIR"
  cd "$CONFIG_DIR"
  
  # Check if the branch exists
  if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    log "WARNING: Branch $BRANCH does not exist locally. Attempting to fetch it."
    if ! git fetch origin "$BRANCH"; then
      log "ERROR: Branch $BRANCH does not exist on remote."
      exit 1
    fi
    git checkout "$BRANCH"
  fi
  
  CURRENT_COMMIT=$(git rev-parse HEAD)
  log "Current commit: $CURRENT_COMMIT"
fi

# Setup SSH keys if provided
if [ -n "$SSH_PRIVATE_KEY" ]; then
  log "Setting up SSH keys"
  mkdir -p /root/.ssh
  umask 077 # Ensure secure permissions
  echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  
  # Add github.com to known hosts
  if ! ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null; then
    log "WARNING: Failed to add GitHub to known hosts"
  fi
  
  # Configure git to use SSH
  cd "$CONFIG_DIR"
  REPO_SSH_URL=$(echo "$REPO_URL" | sed 's|https://github.com/|git@github.com:|')
  git remote set-url origin "$REPO_SSH_URL"
  log "SSH keys configured. Using SSH URL: $REPO_SSH_URL"
fi

# Function to restart Nginx
restart_nginx() {
  log "Restarting Nginx container: $NGINX_CONTAINER_NAME"
  
  # Check if docker compose file exists
  if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ]; then
    log "ERROR: No docker-compose.yml or compose.yml file found"
    return 1
  fi
  
  # Restart the container
  if docker compose down && docker compose build && docker compose up -d "$NGINX_CONTAINER_NAME"; then
    log "Nginx container restarted successfully"
    return 0
  else
    log "Failed to restart Nginx container"
    return 1
  fi
}

# Continuous monitoring loop
log "Starting monitoring of $REPO_URL (branch: $BRANCH)"
log "Checking every $WATCH_INTERVAL seconds"

while true; do
  cd "$CONFIG_DIR" || { log "ERROR: Cannot change to $CONFIG_DIR"; sleep "$WATCH_INTERVAL"; continue; }
  
  # Fetch latest changes
  log "Fetching latest changes from remote"
  if ! git fetch origin "$BRANCH"; then
    log "ERROR: Failed to fetch from remote, will retry next interval"
    sleep "$WATCH_INTERVAL"
    continue
  fi
  
  # Get the latest commit hash
  REMOTE_COMMIT=$(git rev-parse origin/"$BRANCH")
  log "Remote commit: $REMOTE_COMMIT"
  log "Current commit: $CURRENT_COMMIT"
  
  # Check if there are changes
  if [ "$REMOTE_COMMIT" != "$CURRENT_COMMIT" ]; then
    log "Changes detected, pulling latest code"
    
    # Save current state in case pull fails
    git rev-parse HEAD > /tmp/previous_commit
    
    # Pull changes
    if ! git pull origin "$BRANCH"; then
      log "ERROR: Failed to pull changes, checking for conflicts"
      if git status | grep -q 'You have unmerged paths'; then
        log "ERROR: Merge conflicts detected. Reverting to previous state."
        git reset --hard "$(cat /tmp/previous_commit)"
        sleep "$WATCH_INTERVAL"
        continue
      fi
    fi
    
    CURRENT_COMMIT="$REMOTE_COMMIT"
    
    # Verify Nginx configuration files exist
    if ! find "$CONFIG_DIR" -name "*.conf" -o -name "nginx.conf" | grep -q .; then
      log "WARNING: No Nginx configuration files found in the repository"
    fi
    
    # Restart Nginx container
    restart_nginx
  else
    log "No changes detected"
  fi
  
  # Wait for next check
  log "Sleeping for $WATCH_INTERVAL seconds"
  sleep "$WATCH_INTERVAL"
done