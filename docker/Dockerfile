FROM node:23.11.0-slim

# Add labels for better container management
LABEL maintainer="Odoo SFU Team" \
      description="Odoo SFU (Selective Forwarding Unit) for WebRTC" \
      version="1.0"

# Working directory inside the container
WORKDIR /app

# Install necessary dependencies with security best practices
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && npm config set fund false \
    && npm config set audit false

# Copy package.json files first for better layer caching
COPY package*.json ./

# Install dependencies
RUN npm ci --omit=dev \
    && npm cache clean --force

# Copy the rest of the application code
COPY . .

# Build the client bundle
RUN npm run build

# Create a non-root user and set permissions
RUN groupadd -r sfu && useradd -r -g sfu sfu \
    && chown -R sfu:sfu /app

# Switch to non-root user
USER sfu

# Set only internal defaults for container operation
# All configurable values should come from environment variables
ENV HTTP_INTERFACE="0.0.0.0" \
    PORT=8070 \
    RTC_INTERFACE="0.0.0.0" \
    NODE_ENV="production"

# Expose SFU HTTP/WS port
EXPOSE 8070

# Expose RTC ports range
EXPOSE 40000-49999/tcp
EXPOSE 40000-49999/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8070/v1/noop || exit 1

# Start the SFU server
CMD ["npm", "start"]