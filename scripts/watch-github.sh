#!/bin/bash

# Exit on any error, undefined variable reference, or pipe failure
set -euo pipefail

# Configuration with defaults
REPO_URL=${REPO_URL:-"https://github.com/nuniesmith/nginx.git"}
BRANCH=${BRANCH:-"main"}
WATCH_INTERVAL=${WATCH_INTERVAL:-300}
NGINX_CONTAINER_NAME=${NGINX_CONTAINER_NAME:-"nginx"}
CONFIG_DIR=${CONFIG_DIR:-"/app/config"}
LOCKFILE="/var/run/nginx_config_watcher.lock"
USE_DOCKER_COMPOSE=${USE_DOCKER_COMPOSE:-"true"}
COMPOSE_FILE=${COMPOSE_FILE:-"docker-compose.yml"}
COMPOSE_DIR=${COMPOSE_DIR:-"$CONFIG_DIR"}
VERBOSE=${VERBOSE:-"false"}
DISABLE_RESTART=${DISABLE_RESTART:-"false"}
HEALTHCHECK_URL=${HEALTHCHECK_URL:-""}

# Function to log with timestamp and severity
log() {
  local level="INFO"
  if [ $# -eq 2 ]; then
    level="$1"
    shift
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
  
  # If error and we have a health check URL, notify of failure
  if [ "$level" = "ERROR" ] && [ -n "$HEALTHCHECK_URL" ]; then
    curl -s -m 10 --retry 3 "$HEALTHCHECK_URL/fail" -d "Error: $1" || true
  fi
}

# Function for verbose logging
vlog() {
  if [ "$VERBOSE" = "true" ]; then
    log "$@"
  fi
}

# Function for cleanup
cleanup() {
  log "Received shutdown signal, exiting gracefully"
  [ -f "$LOCKFILE" ] && rm -f "$LOCKFILE"
  exit 0
}

# Setup trap for signals
trap cleanup SIGINT SIGTERM EXIT

# Function to check dependencies
check_dependencies() {
  local missing_deps=0
  
  # Check for git
  if ! command -v git >/dev/null 2>&1; then
    log "ERROR" "Git is not installed or not in PATH"
    missing_deps=1
  fi
  
  # Check for Docker
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR" "Docker is not installed or not in PATH"
    missing_deps=1
  fi
  
  # Check for Docker Compose if needed
  if [ "$USE_DOCKER_COMPOSE" = "true" ] && ! docker compose version >/dev/null 2>&1; then
    log "WARNING" "Docker Compose V2 not available. Falling back to 'docker-compose' command."
    
    # Check for docker-compose as fallback
    if ! command -v docker-compose >/dev/null 2>&1; then
      log "ERROR" "Neither 'docker compose' nor 'docker-compose' are available in PATH"
      missing_deps=1
    else
      # If docker-compose exists, use it instead
      USE_DOCKER_COMPOSE="legacy"
    fi
  fi
  
  return $missing_deps
}

# Check for running instance
check_running_instance() {
  if [ -e "$LOCKFILE" ]; then
    if kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
      log "ERROR" "Script is already running with PID $(cat "$LOCKFILE")"
      return 1
    else
      log "WARNING" "Found stale lockfile, removing"
      rm -f "$LOCKFILE"
    fi
  fi
  echo $$ > "$LOCKFILE"
  return 0
}

# Function to setup git repository
setup_git_repo() {
  # Initial setup
  if [ ! -d "$CONFIG_DIR/.git" ]; then
    log "Performing initial clone of $REPO_URL to $CONFIG_DIR"
    # If CONFIG_DIR exists but is not a git repo, we need to clear it
    if [ -d "$CONFIG_DIR" ]; then
      log "WARNING" "Directory exists but is not a git repository. Removing contents."
      rm -rf "$CONFIG_DIR"
    fi
    
    mkdir -p "$CONFIG_DIR"
    
    if ! git clone -b "$BRANCH" "$REPO_URL" "$CONFIG_DIR"; then
      log "ERROR" "Failed to clone repository"
      return 1
    fi
    
    CURRENT_COMMIT=$(cd "$CONFIG_DIR" && git rev-parse HEAD)
    log "Initial clone complete. Current commit: $CURRENT_COMMIT"
  else
    log "Git repository already exists in $CONFIG_DIR"
    cd "$CONFIG_DIR" || { log "ERROR" "Cannot change to $CONFIG_DIR"; return 1; }
    
    # Make sure we're on the right branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    if [ "$current_branch" != "$BRANCH" ]; then
      log "Switching from branch $current_branch to $BRANCH"
      
      # Stash any changes to avoid conflicts
      if git status --porcelain | grep -q .; then
        log "WARNING" "Uncommitted changes found, stashing them"
        git stash
      fi
      
      # Check if the branch exists locally
      if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git checkout "$BRANCH"
      else
        # Try to fetch and checkout the branch
        if ! git fetch origin "$BRANCH" && git checkout -b "$BRANCH" "origin/$BRANCH"; then
          log "ERROR" "Branch $BRANCH does not exist or cannot be checked out"
          return 1
        fi
      fi
    fi
    
    CURRENT_COMMIT=$(git rev-parse HEAD)
    log "Current commit: $CURRENT_COMMIT"
  fi
  
  return 0
}

# Setup SSH keys if provided
setup_ssh_keys() {
  if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    log "Setting up SSH keys"
    mkdir -p /root/.ssh
    umask 077 # Ensure secure permissions
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    
    # Add github.com to known hosts
    if ! ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null; then
      log "WARNING" "Failed to add GitHub to known hosts"
    fi
    
    # Configure git to use SSH
    cd "$CONFIG_DIR" || { log "ERROR" "Cannot change to $CONFIG_DIR"; return 1; }
    
    # Determine if it's a GitHub URL and convert accordingly
    if echo "$REPO_URL" | grep -q "github.com"; then
      REPO_SSH_URL=$(echo "$REPO_URL" | sed 's|https://github.com/|git@github.com:|')
      git remote set-url origin "$REPO_SSH_URL"
      log "SSH keys configured. Using SSH URL: $REPO_SSH_URL"
    else
      log "WARNING" "Repository is not on GitHub, manual SSH URL conversion not performed"
    fi
  fi
  
  return 0
}

# Function to check Docker container status
check_container_status() {
  local container_name="$1"
  
  if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    vlog "Container $container_name is running"
    return 0
  elif docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    log "WARNING" "Container $container_name exists but is not running"
    return 1
  else
    log "WARNING" "Container $container_name does not exist"
    return 2
  fi
}

# Function to validate Nginx configuration
validate_nginx_config() {
  # Look for Nginx configuration files
  if ! find "$CONFIG_DIR" -name "*.conf" -o -name "nginx.conf" | grep -q .; then
    log "WARNING" "No Nginx configuration files found in the repository"
    return 1
  fi
  
  return 0
}

# Function to restart Nginx
restart_nginx() {
  if [ "$DISABLE_RESTART" = "true" ]; then
    log "Container restart is disabled by configuration. Skipping."
    return 0
  fi
  
  log "Restarting Nginx container: $NGINX_CONTAINER_NAME"
  
  # Check for Docker Compose configuration
  if [ "$USE_DOCKER_COMPOSE" = "true" ] || [ "$USE_DOCKER_COMPOSE" = "legacy" ]; then
    cd "$COMPOSE_DIR" || { log "ERROR" "Cannot change to $COMPOSE_DIR"; return 1; }
    
    local compose_cmd="docker compose"
    if [ "$USE_DOCKER_COMPOSE" = "legacy" ]; then
      compose_cmd="docker-compose"
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ] && [ ! -f "compose.yml" ]; then
      log "ERROR" "No $COMPOSE_FILE or compose.yml file found in $COMPOSE_DIR"
      return 1
    fi
    
    local compose_file_arg=""
    if [ -f "$COMPOSE_FILE" ]; then
      compose_file_arg="-f $COMPOSE_FILE"
    fi
    
    # Restart the container using Docker Compose
    vlog "Executing: $compose_cmd $compose_file_arg down && $compose_cmd $compose_file_arg build && $compose_cmd $compose_file_arg up -d"
    
    # shellcheck disable=SC2086
    if $compose_cmd $compose_file_arg down && \
       $compose_cmd $compose_file_arg build && \
       $compose_cmd $compose_file_arg up -d; then
      log "Nginx container restarted successfully with Docker Compose"
      return 0
    else
      log "ERROR" "Failed to restart Nginx container with Docker Compose"
      return 1
    fi
  else
    # Use direct Docker commands instead of Docker Compose
    local container_status
    check_container_status "$NGINX_CONTAINER_NAME"
    container_status=$?
    
    if [ $container_status -eq 0 ]; then
      # Container is running, just restart it
      if docker restart "$NGINX_CONTAINER_NAME"; then
        log "Nginx container restarted successfully"
        return 0
      else
        log "ERROR" "Failed to restart Nginx container"
        return 1
      fi
    elif [ $container_status -eq 1 ]; then
      # Container exists but is not running
      if docker start "$NGINX_CONTAINER_NAME"; then
        log "Nginx container started successfully"
        return 0
      else
        log "ERROR" "Failed to start Nginx container"
        return 1
      fi
    else
      log "ERROR" "Nginx container does not exist and cannot be restarted without Docker Compose"
      return 1
    fi
  fi
}

# Function to pull latest changes
pull_latest_changes() {
  cd "$CONFIG_DIR" || { log "ERROR" "Cannot change to $CONFIG_DIR"; return 1; }
  
  # Save current state in case pull fails
  git rev-parse HEAD > /tmp/previous_commit
  
  # Fetch latest changes
  log "Fetching latest changes from remote"
  if ! git fetch origin "$BRANCH"; then
    log "ERROR" "Failed to fetch from remote"
    return 1
  fi
  
  # Get the latest commit hash
  REMOTE_COMMIT=$(git rev-parse origin/"$BRANCH")
  vlog "Remote commit: $REMOTE_COMMIT"
  vlog "Current commit: $CURRENT_COMMIT"
  
  # Check if there are changes
  if [ "$REMOTE_COMMIT" != "$CURRENT_COMMIT" ]; then
    log "Changes detected, pulling latest code"
    
    # Check for local changes
    if git status --porcelain | grep -q .; then
      log "WARNING" "Local uncommitted changes detected. Stashing them."
      git stash
    fi
    
    # Pull changes
    if ! git pull origin "$BRANCH"; then
      log "ERROR" "Failed to pull changes, checking for conflicts"
      if git status | grep -q 'You have unmerged paths'; then
        log "ERROR" "Merge conflicts detected. Reverting to previous state."
        git reset --hard "$(cat /tmp/previous_commit)"
        return 1
      fi
    fi
    
    CURRENT_COMMIT="$REMOTE_COMMIT"
    
    # Validate the Nginx configuration
    validate_nginx_config
    
    # Restart Nginx container
    restart_nginx
    return $?
  else
    vlog "No changes detected"
    return 0
  fi
}

# Main function to execute the script
main() {
  # Check dependencies
  check_dependencies || exit 1
  
  # Check for running instance
  check_running_instance || exit 1
  
  # Setup git repository
  setup_git_repo || exit 1
  
  # Setup SSH keys if provided
  setup_ssh_keys || log "WARNING" "Failed to set up SSH keys"
  
  # Continuous monitoring loop
  log "Starting monitoring of $REPO_URL (branch: $BRANCH)"
  log "Checking every $WATCH_INTERVAL seconds"
  
  # Notify health check URL if provided
  if [ -n "$HEALTHCHECK_URL" ]; then
    curl -s -m 10 --retry 3 "$HEALTHCHECK_URL" -d "Monitoring started" || \
      log "WARNING" "Failed to ping health check URL"
  fi
  
  while true; do
    pull_latest_changes || log "WARNING" "Update cycle failed, will retry next interval"
    
    # Wait for next check
    vlog "Sleeping for $WATCH_INTERVAL seconds"
    sleep "$WATCH_INTERVAL"
  done
}

# Execute main function
main