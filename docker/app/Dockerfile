FROM alpine:latest

# Install required packages
RUN apk update && \
    apk add --no-cache git curl bash openssh-client

# Create app directory
WORKDIR /app

# Copy the monitoring script
COPY ./scripts/watch-github.sh /app/

# Make the script executable
RUN chmod +x /app/watch-github.sh

# Set environment variables (can be overridden)
ENV REPO_URL="https://github.com/nuniesmith/nginx.git"
ENV BRANCH="main"
ENV WATCH_INTERVAL=300
ENV NGINX_CONTAINER_NAME="nginx"
ENV CONFIG_DIR="/app/config"

# Run the script
CMD ["/app/watch-github.sh"]