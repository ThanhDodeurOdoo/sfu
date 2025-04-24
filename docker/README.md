# Odoo SFU Docker Deployment Guide

This is an example of Odoo SFU deployment using Docker and nginx.

## Overview

The deployment provides:

- Containerized SFU server with proper isolation
- Nginx reverse proxy with SSL termination
- Automated setup and configuration
- Monitoring and maintenance tools

## Requirements

- Linux-based server (tested on Ubuntu 20.04/22.04)
- Node JS / NPM at the version supported by the SFU
- Docker and Docker Compose installed
- Public IP address with ports accessible:
  - 80/443 TCP (HTTP/HTTPS)
  - 8070 TCP (SFU WebSocket)
  - 40000-49999 TCP/UDP (WebRTC media)
- Domain name with DNS records pointing to your server (recommended for production)

## Quick Start

1. **Clone the repository to your server**

   ```bash
   git clone git@github.com:ThanhDodeurOdoo/sfu.git
   cd sfu/docker
   ```

2. **Run the setup script**

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

   The setup script will:
   - Create necessary directories
   - Generate configuration files
   - Create .env file with required variables
   - Generate or use existing SSL certificates
   - Configure Nginx

3. **Open required ports in your firewall**

   ```bash
   sudo ./open-ports.sh
   ```

4. **Start the SFU**

   ```bash
   docker compose up -d
   ```

5. **Configure your Odoo instance**

   In your Odoo settings, configure:
   - RTC Server URL: `https://your-domain.com` (or `https://your-server-ip`)
   - RTC Server KEY: The AUTH_KEY value (from .env file)

## Configuration Options

The most important env variables are:

| Variable | Description | Default |
|----------|-------------|---------|
| `PUBLIC_IP` | Public IP address of the server | Auto-detected |
| `AUTH_KEY` | Authentication key for JWT tokens | Generated on setup |
| `DOMAIN_NAME` | Your domain (if using one) | Prompted if missing |

For an exhaustive list, refer to the SFU documentation.

To update configuration:

```bash
./update-env.sh KEY1=VALUE1 KEY2=VALUE2
```

## SSL Certificate Setup

### Using Let's Encrypt (Production)

If you're using a domain name:

```bash
sudo ./setup-letsencrypt.sh
```

### Self-signed Certificates (Development/Testing)

For testing environments:

```bash
./generate-self-signed-cert.sh
```

## Maintenance

### Monitoring

The monitoring script provides information about the health and performance of your SFU:

```bash
./monitor.sh
```

This shows:
- Container status
- Resource usage
- Error logs
- Active connections
- SSL certificate information
- System load

Set up regular monitoring with cron:

```bash
crontab -e
# Add: */15 * * * * cd /path/to/docker && ./monitor.sh > /var/log/sfu-monitor.log 2>&1
```

or

```bash
docker logs [--tail number] process-name
docker logs --tail 10 odoo-sfu
docker logs --tail 10 sfu-nginx
```

### Backups

Back up your configuration regularly:

```bash
./backup.sh
```

By default, backups are stored in `/var/backups/odoo-sfu/`. Set up a backup schedule:

```bash
crontab -e
# Add: 0 3 * * * cd /path/to/docker && ./backup.sh
```

### Updates

To update the SFU:

1. Pull the latest changes
   ```bash
   git pull
   ```

2. Rebuild and restart the containers
   ```bash
   docker compose down
   docker compose up -d --build
   ```

## Network Configuration

For optimal WebRTC performance, ensure:

- UDP ports 40000-49999 are properly forwarded in your firewall and network settings
- The PUBLIC_IP value in your .env file is correctly set to your server's public IP
- Your hosting provider or network doesn't have UDP rate limiting that could affect WebRTC connections

## Troubleshooting

### WebRTC Connection Issues

1. **Verify ports are open**:
   ```bash
   sudo iptables -L -n
   nc -vz -u your_server_ip 40500
   ```

2. **Check SFU logs**:
   ```bash
   docker logs odoo-sfu
   ```

3. **Verify Nginx configuration**:
   ```bash
   docker exec sfu-nginx nginx -t
   ```

4. **Test SFU API endpoint**:
   ```bash
   curl -k https://your-domain.com/v1/noop
   ```

### Common Issues

1. **"Failed to connect to SFU" in Odoo**:
   - Verify AUTH_KEY matches between SFU and Odoo
   - Check SSL certificate validity
   - Ensure WebRTC ports are open

2. **Poor video/audio quality**:
   - Check network bandwidth between participants
   - Adjust MAX_BITRATE settings in .env
   - Consider upgrading server resources

3. **High CPU usage**:
   - Adjust NUM_WORKERS to a lower value
   - Monitor with `./monitor.sh`
   - Consider resource limits in docker-compose.yml

## Security Considerations

1. Keep your AUTH_KEY secure - this is the primary authentication mechanism
2. Regularly update your system and Docker images
3. Use Let's Encrypt for valid SSL certificates in production
4. Implement proper firewall rules with `./open-ports.sh`
5. Consider adding basic authentication for the /v1/ API endpoints
