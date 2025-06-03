# SFU Monitor Dashboard

A web-based monitoring dashboard for your Odoo SFU deployment that provides real-time logs, system health monitoring, and channel statistics.

## Features

- **Real-time Docker Logs**: View SFU container logs with filtering and auto-refresh
- **System Health Monitoring**: Check SFU availability and response status
- **Channel Statistics**: Monitor active channels, sessions, and bitrates
- **Protected Access**: HTTP Basic Authentication using existing nginx credentials
- **Auto-refresh**: Configurable automatic updates every 30 seconds
- **Responsive Design**: Works on desktop and mobile devices

## Installation

### Prerequisites

- Docker and Docker Compose installed
- Existing SFU deployment running
- Existing nginx stats authentication configured (via users.sh script)
- Access to modify nginx configuration

### Setup Steps

1. **Create the required files in your docker directory:**

   ```bash
   cd /path/to/your/sfu/docker
   ```

2. **Create `monitor.html`** - Copy the HTML content from the provided artifact

3. **Create `monitor-server.js`** - Copy the JavaScript server code from the provided artifact

4. **Make the server executable:**
   ```bash
   chmod +x monitor-server.js
   ```

5. **Run the setup script:**
   ```bash
   ./setup-monitor.sh
   ```

   Or manually follow these steps:

### Manual Setup

1. **Ensure you have nginx stats authentication configured:**
   ```bash
   ./users.sh add your_username  # If not already done
   ```

2. **Update `docker-compose.yml`** to add the monitor service:
   ```yaml
   monitor:
     image: node:23.11.0-slim
     container_name: sfu-monitor
     working_dir: /app
     volumes:
       - ./monitor.html:/app/monitor.html:ro
       - ./monitor-server.js:/app/server.js:ro
       - /var/run/docker.sock:/var/run/docker.sock:ro
     command: node server.js
     restart: unless-stopped
     ports:
       - "8071:8071"
     depends_on:
       - sfu
   ```

3. **Update nginx configuration** (`nginx/conf.d/default.conf`) to add these location blocks inside your HTTPS server block:

   ```nginx
   # SFU Monitor Dashboard (protected)
   location /monitor {
       auth_basic "SFU Monitor Access";
       auth_basic_user_file /etc/nginx/stats_auth;
       
       rewrite ^/monitor/?(.*) /$1 break;
       
       proxy_pass http://localhost:8071;
       proxy_http_version 1.1;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       
       proxy_read_timeout 60s;
       proxy_send_timeout 60s;
   }
   
   # API endpoints for monitor
   location ~ ^/monitor-api/(logs|health) {
       auth_basic "SFU Monitor API";
       auth_basic_user_file /etc/nginx/stats_auth;
       
       rewrite ^/monitor-api/(.*) /$1 break;
       
       proxy_pass http://localhost:8071;
       proxy_http_version 1.1;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
   }
   ```

4. **Restart services:**
   ```bash
   docker compose down
   docker compose up -d
   ```

## Usage

### Accessing the Dashboard

1. Open your browser and navigate to: `https://tso-sfu-001.eu/monitor`
2. Log in using your existing nginx stats credentials:
   - Same username/password as used for `/v1/stats` endpoint
   - Managed via `./users.sh` script or directly in `nginx/ssl/stats_auth`

### Dashboard Features

- **Status Indicator**: Green dot = SFU is healthy, Red = offline, Orange = degraded
- **Log Viewer**: Real-time container logs with filtering by log level
- **Controls**:
  - Refresh Logs: Manually refresh the log display
  - Clear Display: Clear the current log view
  - Auto-refresh: Toggle automatic refresh every 30 seconds
  - Log Lines: Choose how many log lines to display (100-1000)
- **Statistics Panel**:
  - SFU Health status
  - Channel count and session statistics
  - System information and last update time

### API Endpoints

The monitor also provides API endpoints (protected by the same auth):

- `GET /monitor-api/health` - Health check endpoint
- `GET /monitor-api/logs?lines=200` - Fetch Docker logs (max 2000 lines)

## Configuration

### Authentication

The monitor uses your existing nginx stats authentication system:
- **No separate passwords needed**
- Uses the same credentials as `/v1/stats` endpoint
- Managed via the `users.sh` script in your docker directory
- Authentication is handled entirely by nginx

### Adding/Managing Users

```bash
# Add a new user
./users.sh add monitoring_user

# List existing users  
./users.sh list

# Remove a user
./users.sh remove old_user
```

### Security Notes

- The monitor uses the same HTTP Basic Auth as your nginx stats endpoint
- **No additional password management required**
- All requests are logged for security auditing
- Docker socket access is read-only for fetching logs
- No sensitive SFU configuration is exposed through the monitor
- Authentication is handled by nginx using the existing `stats_auth` file

## Troubleshooting

### Monitor Service Won't Start

1. Check Docker socket permissions:
   ```bash
   ls -la /var/run/docker.sock
   ```

2. Check monitor container logs:
   ```bash
   docker logs sfu-monitor
   ```

### Can't Access Dashboard

1. Verify nginx configuration:
   ```bash
   docker exec sfu-nginx nginx -t
   ```

2. Check if monitor service is running:
   ```bash
   docker ps | grep sfu-monitor
   ```

3. Test API endpoint directly:
   ```bash
   curl -u your_username:your_password https://tso-sfu-001.eu/monitor-api/health
   ```

### Logs Not Showing

1. Verify SFU container name in monitor-server.js (should be `odoo-sfu`)
2. Check if the SFU container is running:
   ```bash
   docker ps | grep odoo-sfu
   ```

### Common Issues

- **403 Forbidden**: Check your nginx stats auth credentials
- **502 Bad Gateway**: Monitor service might not be running
- **Empty logs**: SFU container might not be generating logs or name mismatch

## Customization

### Changing Refresh Interval

Edit the `CONFIG.REFRESH_INTERVAL` value in `monitor.html` (default: 30000ms)

### Adding More Log Filtering

Modify the `getLogLevel()` function in `monitor.html` to add custom log level detection

### Styling

The dashboard uses a dark theme optimized for monitoring. CSS can be customized in the `<style>` section of `monitor.html`

## Security Best Practices

1. **Use existing stats auth**: Monitor leverages your existing nginx authentication
2. **Use HTTPS**: The monitor should only be accessed over HTTPS  
3. **Limit access**: Consider restricting access by IP if possible
4. **Regular updates**: Keep the Node.js base image updated
5. **Monitor access logs**: Check nginx logs for unauthorized access attempts
6. **Manage users properly**: Use `./users.sh` to manage access credentials

## File Structure

```
docker/
├── monitor.html              # Dashboard HTML page
├── monitor-server.js         # Node.js API server
├── setup-monitor.sh          # Setup script
├── docker-compose.yml        # Updated with monitor service
└── nginx/conf.d/default.conf # Updated with monitor routes
```
