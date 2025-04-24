# Running Odoo SFU with Docker

This guide explains how to run the Odoo SFU (Selective Forwarding Unit) using Docker and Docker Compose.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- A server with a public IP address
- Ports 80, 8070, and 40000-49999 (TCP/UDP) open in your firewall

## Quick Start

1. Navigate to the docker directory:
   ```bash
   cd docker
   ```

2. Run the setup script:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```
   This script will:
   - Create necessary directories
   - Set up Nginx configuration
   - Detect your public IP
   - Generate a secure AUTH_KEY
   - Create a `.env` file with your configuration

3. Start the containers:
   ```bash
   docker compose up -d
   ```

4. Verify the SFU is running:
   ```bash
   curl http://localhost:8070/v1/noop
   # Should return: {"result":"ok"}
   ```

## Configuration

The main configuration is stored in the `.env` file in the docker directory:

- `PUBLIC_IP`: Your server's public IP address (required)
- `AUTH_KEY`: Secret key used for authentication (required)
- `NUM_WORKERS`: Number of worker processes (default: number of CPU cores minus 1)

You can modify these values directly in the `.env` file.

## Connecting Odoo to Your SFU

In your Odoo instance:

1. Go to the Discuss settings
2. Configure:
   - **RTC Server URL**: `http://your-public-ip` (or your domain if you've set one up)
   - **RTC Server KEY**: The AUTH_KEY value from your `.env` file

## Useful Commands

- Start the SFU (from the docker directory):
  ```bash
  docker compose up -d
  ```

- View logs:
  ```bash
  docker compose logs -f
  ```

- Stop the SFU:
  ```bash
  docker compose down
  ```

- Rebuild and restart (after code changes):
  ```bash
  docker compose build --no-cache
  docker compose up -d
  ```

## Advanced Configuration

### SSL/HTTPS

To enable HTTPS:

1. Obtain SSL certificates (e.g., using Let's Encrypt)
2. Place them in the `docker/nginx/ssl` directory:
   - `fullchain.pem`
   - `privkey.pem`
3. Uncomment the HTTPS server block in `docker/nginx/conf.d/default.conf`
4. Update the `server_name` directive with your domain
5. Restart the containers:
   ```bash
   docker compose restart
   ```

### Custom Ports

If you need to use different ports, modify the `ports` section in `docker-compose.yml`.

### Performance Tuning

For better performance:

1. Adjust `NUM_WORKERS` in the `.env` file according to your server's CPU cores
2. Modify the bitrate settings in `docker-compose.yml` if needed:
   - `MAX_BITRATE_IN`: Maximum incoming bitrate per session
   - `MAX_BITRATE_OUT`: Maximum outgoing bitrate per session
   - `MAX_VIDEO_BITRATE`: Maximum bitrate for video

## Troubleshooting

### Connection Issues

1. Verify that ports are open in your firewall:
   ```bash
   sudo ufw status
   ```

2. Check container logs:
   ```bash
   docker compose logs -f
   ```

3. Test the SFU endpoint:
   ```bash
   curl http://localhost:8070/v1/noop
   ```

### WebRTC Issues

If you're experiencing WebRTC connection problems:

1. Ensure `PUBLIC_IP` is set correctly to your server's public IP
2. Verify that UDP ports 40000-49999 are open
3. Check for NAT/firewall issues on your network

### Container Issues

If containers aren't starting:

```bash
# Check container status
docker ps -a

# View detailed container information
docker inspect odoo-sfu

# Check container logs
docker logs odoo-sfu
```

## Security Considerations

- Keep your AUTH_KEY secure
- Consider enabling HTTPS for production use
- Regularly update your Docker images
- Monitor logs for unusual activity

## Resource Usage

The SFU can be resource-intensive with multiple video streams. Monitor your server's resource usage:

```bash
# Check CPU and memory usage
docker stats

# Monitor system resources
htop
```