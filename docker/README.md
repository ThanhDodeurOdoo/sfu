# Odoo SFU Docker Deployment Guide (OVH VPS)

This guide provides instructions for deploying the Odoo Selective Forwarding Unit (SFU) on an OVH VPS using Docker and Nginx.

## Requirements

- An OVH VPS with Ubuntu 20.04 or newer
- A custom domain name (recommended for production)
- Docker and Docker Compose installed
- Ports 80, 443, 8070, and 40000-49999 (TCP/UDP) accessible

## Quick Start

1. **Clone or transfer this repository to your VPS**

2. **Run the setup script:**
   ```bash
   cd docker
   chmod +x setup.sh
   ./setup.sh
   ```

3. **Open required ports:**
   ```bash
   sudo ./open-ports.sh
   ```

4. **Start the SFU:**
   ```bash
   docker compose up -d
   ```

5. **Configure your Odoo instance:**
   - RTC Server URL: `https://your-domain.com` or `https://your-server-ip`
   - RTC Server KEY: The AUTH_KEY value (from .env file)

## Directory Structure

```
docker/
├── docker-compose.yml          # Docker Compose configuration
├── Dockerfile                  # SFU container build instructions
├── .env                        # Environment variables (created by setup.sh)
├── .env.example               # Example environment variables
├── setup.sh                    # Setup script for initial configuration
├── backup.sh                   # Backup script for configurations
├── monitor.sh                  # Monitoring script for system health
├── open-ports.sh               # Script to configure firewall rules
└── nginx/
    ├── conf.d/                 # Nginx configuration
    └── ssl/                    # SSL certificates
```

## OVH-Specific Considerations

### 1. Network Configuration

OVH VPS instances require specific network configuration for optimal WebRTC performance:

- Verify that UDP ports 40000-49999 are open in the OVH firewall
- Set the correct PUBLIC_IP in your .env file
- If you have issues with WebRTC connectivity, contact OVH support about UDP traffic policies

### 2. Domain Configuration

If using a custom domain purchased through OVH:

- Set up DNS records pointing to your VPS IP address
- A record: `@` → Your VPS IP address
- A record: `www` → Your VPS IP address
- Wait for DNS propagation (can take up to 24 hours)

### 3. SSL Certificate Setup

For production environments, obtain a Let's Encrypt certificate:

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com -d www.your-domain.com
```

## Maintenance

### Monitoring

Run the monitoring script to check system health:

```bash
./monitor.sh
```

Set up a cron job for regular monitoring:

```bash
crontab -e
# Add: */15 * * * * cd /path/to/docker && ./monitor.sh > /var/log/sfu-monitor.log 2>&1
```

### Backups

Run the backup script to save your configuration:

```bash
./backup.sh
```

Set up a cron job for daily backups:

```bash
crontab -e
# Add: 0 3 * * * cd /path/to/docker && ./backup.sh
```

### Updates

To update the SFU:

```bash
# Pull latest changes
git pull

# Rebuild and restart
docker compose down
docker compose build --no-cache
docker compose up -d
```

## Troubleshooting

### WebRTC Connection Issues

If you experience connection problems:

1. Verify UDP port connectivity:
   ```bash
   sudo apt install -y netcat
   nc -l -u -p 40500  # Run on server
   # From another machine: nc -u your_vps_ip 40500
   ```

2. Check SSL certificates:
   ```bash
   openssl x509 -in nginx/ssl/fullchain.pem -text -noout
   ```

3. Verify Nginx configuration:
   ```bash
   docker exec sfu-nginx nginx -t
   ```

4. Check container logs:
   ```bash
   docker logs odoo-sfu
   docker logs sfu-nginx
   ```

### OVH-Specific Issues

1. **IPv6 Connectivity:** If you're using IPv6, add this to your docker-compose.yml:
   ```yaml
   services:
     sfu:
       enable_ipv6: true
     nginx:
       enable_ipv6: true
   ```

2. **Resource Limits:** Adjust CPU_LIMIT and MEMORY_LIMIT in .env based on your VPS plan

3. **Network Performance:** Consider upgrading to OVH's High Network Performance option for better WebRTC quality

## Security Recommendations

1. Keep your AUTH_KEY private and secure
2. Regularly update your system and Docker images
3. Implement regular backups to OVH Object Storage
4. Monitor logs for suspicious activity
5. Consider adding basic authentication for the /v1/ API endpoints

## Contact and Support

For issues with this deployment configuration, please open an issue in the repository.

For OVH VPS issues, contact OVH support through your control panel.