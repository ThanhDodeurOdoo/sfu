#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// Configuration
const CONFIG = {
    PORT: 8071,
    LOG_LINES_DEFAULT: 200,
    LOG_LINES_MAX: 2000,
    CONTAINER_NAME: 'odoo-sfu'
};

// MIME types for static files
const MIME_TYPES = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json'
};

function getMimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    return MIME_TYPES[ext] || 'text/plain';
}

function getDockerLogs(lines = CONFIG.LOG_LINES_DEFAULT) {
    return new Promise((resolve, reject) => {
        const maxLines = Math.min(lines, CONFIG.LOG_LINES_MAX);
        const dockerLogs = spawn('docker', ['logs', '--tail', maxLines.toString(), CONFIG.CONTAINER_NAME]);

        let stdout = '';
        let stderr = '';

        dockerLogs.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        dockerLogs.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        dockerLogs.on('close', (code) => {
            if (code === 0) {
                let allLogs = (stderr + stdout).trim();
                // Strip ANSI color codes
                allLogs = allLogs.replace(/\x1b\[[0-9;]*m/g, '');
                resolve(allLogs);
            } else {
                reject(new Error(`Docker logs command failed with code ${code}`));
            }
        });

        dockerLogs.on('error', (error) => {
            reject(new Error(`Failed to execute docker logs: ${error.message}`));
        });

        setTimeout(() => {
            dockerLogs.kill();
            reject(new Error('Docker logs command timed out'));
        }, 10000);
    });
}


async function handleRequest(req, res) {
    const url = new URL(req.url, `http://localhost:${CONFIG.PORT}`);
    const pathname = url.pathname;

    console.log(`${new Date().toISOString()} - ${req.method} ${pathname} - ${req.headers['x-forwarded-for'] || req.connection.remoteAddress}`);

    // Handle CORS for API endpoints
    if (req.method === 'OPTIONS') {
        res.writeHead(200, {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        });
        res.end();
        return;
    }

    try {
        if (pathname === '/logs') {
            const lines = parseInt(url.searchParams.get('lines')) || CONFIG.LOG_LINES_DEFAULT;
            console.log(`Fetching ${lines} lines of Docker logs`);
            const logs = await getDockerLogs(lines);

            res.writeHead(200, {
                'Content-Type': 'text/plain',
                'Access-Control-Allow-Origin': '*'
            });
            res.end(logs);
            return;
        }

        if (pathname === '/health') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                status: 'ok',
                timestamp: new Date().toISOString(),
                container: CONFIG.CONTAINER_NAME
            }));
            return;
        }

        if (pathname === '/test') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                message: 'Monitor API is working',
                timestamp: new Date().toISOString(),
                headers: req.headers
            }));
            return;
        }

        // Serve static files
        let filePath;
        if (pathname === '/' || pathname === '/index.html') {
            filePath = path.join(__dirname, 'monitor.html');
        } else {
            // Prevent directory traversal
            const sanitizedPath = pathname.replace(/\.\./g, '').replace(/\/+/g, '/');
            filePath = path.join(__dirname, sanitizedPath);
        }

        // Check if file exists and is readable
        if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('File not found');
            return;
        }

        // Serve the file
        const mimeType = getMimeType(filePath);
        const fileContent = fs.readFileSync(filePath);

        res.writeHead(200, {
            'Content-Type': mimeType,
            'Cache-Control': 'no-cache'
        });
        res.end(fileContent);

    } catch (error) {
        console.error(`Error handling request: ${error.message}`);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end(`Server error: ${error.message}`);
    }
}


const server = http.createServer(handleRequest);

server.listen(CONFIG.PORT, '0.0.0.0', () => {
    console.log(`SFU Monitor server running on port ${CONFIG.PORT}`);
    console.log(`Access the dashboard at: http://localhost:${CONFIG.PORT}/`);
});


process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully');
    server.close(() => {
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully');
    server.close(() => {
        process.exit(0);
    });
});
