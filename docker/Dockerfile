FROM node:20.9.0-slim

# Working directory inside the container
WORKDIR /app

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy package.json files first for better layer caching
COPY package*.json ./

# Install dependencies
RUN npm ci --omit=dev

# Copy the rest of the application code
COPY . .

# Build the client bundle
RUN npm run build

# Set only internal defaults for container operation
# All configurable values should come from environment variables
ENV HTTP_INTERFACE="0.0.0.0"
ENV PORT=8070
ENV RTC_INTERFACE="0.0.0.0"

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