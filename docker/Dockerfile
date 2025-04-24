FROM node:23.11.0-slim

LABEL maintainer="tso" \
      description="Odoo SFU tso docker config" \
      version="1.0"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy package.json files first (separately) for layer caching
COPY package*.json ./

RUN npm install && npm cache clean --force

COPY . .

RUN groupadd -r sfu && useradd -r -g sfu sfu \
    && chown -R sfu:sfu /app
USER sfu

ENV HTTP_INTERFACE="0.0.0.0" \
    PORT=8070 \
    RTC_INTERFACE="0.0.0.0" \
    NODE_ENV="production"

EXPOSE 8070
EXPOSE 40000-49999/tcp
EXPOSE 40000-49999/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8070/v1/noop || exit 1

CMD ["npm", "start"]
