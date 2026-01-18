#!/usr/bin/env python3
"""
LLM Rate Limiter Proxy

A lightweight HTTP proxy that rate-limits requests to llama-server to prevent
GPU MES scheduler crashes caused by too many concurrent batch operations.

Usage:
    ./llm-rate-limiter.py [--port 8080] [--backend http://localhost:8081] [--max-concurrent 5]

The proxy accepts requests on the specified port and forwards them to the backend,
limiting the number of concurrent requests to prevent GPU overload.
"""

import argparse
import http.server
import json
import logging
import queue
import socketserver
import threading
import time
import urllib.error
import urllib.request
from typing import Optional

# Configuration
DEFAULT_PORT = 8080
DEFAULT_BACKEND = "http://localhost:8081"
DEFAULT_MAX_CONCURRENT = 5
DEFAULT_QUEUE_SIZE = 100
REQUEST_TIMEOUT = 600  # 10 minutes for long generations

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class RateLimiter:
    """Semaphore-based rate limiter with queue monitoring."""

    def __init__(self, max_concurrent: int, queue_size: int):
        self.semaphore = threading.Semaphore(max_concurrent)
        self.max_concurrent = max_concurrent
        self.queue_size = queue_size
        self.waiting = 0
        self.active = 0
        self.total_requests = 0
        self.lock = threading.Lock()

    def acquire(self, timeout: Optional[float] = None) -> bool:
        """Acquire a slot, blocking if necessary."""
        with self.lock:
            if self.waiting >= self.queue_size:
                return False  # Queue full
            self.waiting += 1

        acquired = self.semaphore.acquire(timeout=timeout)

        with self.lock:
            self.waiting -= 1
            if acquired:
                self.active += 1
                self.total_requests += 1

        return acquired

    def release(self):
        """Release a slot."""
        with self.lock:
            self.active -= 1
        self.semaphore.release()

    def stats(self) -> dict:
        """Get current stats."""
        with self.lock:
            return {
                "active": self.active,
                "waiting": self.waiting,
                "max_concurrent": self.max_concurrent,
                "total_requests": self.total_requests
            }


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    """HTTP request handler that proxies to backend with rate limiting."""

    backend_url: str = DEFAULT_BACKEND
    rate_limiter: RateLimiter = None

    def log_message(self, format, *args):
        """Override to use our logger."""
        logger.info("%s - %s", self.address_string(), format % args)

    def do_GET(self):
        """Handle GET requests (health, metrics, models)."""
        # Pass through without rate limiting for health checks
        if self.path in ['/health', '/metrics', '/v1/models']:
            self._proxy_request('GET')
        elif self.path == '/proxy/stats':
            self._send_stats()
        else:
            self._proxy_request('GET')

    def do_POST(self):
        """Handle POST requests (completions, chat) with rate limiting."""
        # Rate limit inference requests
        if '/completions' in self.path or '/chat' in self.path:
            if not self.rate_limiter.acquire(timeout=REQUEST_TIMEOUT):
                self._send_error(503, "Server overloaded - queue full")
                return
            try:
                self._proxy_request('POST')
            finally:
                self.rate_limiter.release()
        else:
            self._proxy_request('POST')

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def _send_cors_headers(self):
        """Add CORS headers."""
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

    def _proxy_request(self, method: str):
        """Proxy a request to the backend."""
        url = f"{self.backend_url}{self.path}"

        # Read request body for POST
        body = None
        if method == 'POST':
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                body = self.rfile.read(content_length)

        # Build the request
        req = urllib.request.Request(url, data=body, method=method)

        # Copy relevant headers
        for header in ['Content-Type', 'Authorization', 'Accept']:
            if header in self.headers:
                req.add_header(header, self.headers[header])

        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
                # Send response status
                self.send_response(response.status)

                # Copy response headers
                for header, value in response.getheaders():
                    if header.lower() not in ['transfer-encoding', 'connection']:
                        self.send_header(header, value)
                self._send_cors_headers()
                self.end_headers()

                # Stream response body
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(e.read())
        except urllib.error.URLError as e:
            self._send_error(502, f"Backend error: {e.reason}")
        except Exception as e:
            self._send_error(500, f"Proxy error: {str(e)}")

    def _send_error(self, code: int, message: str):
        """Send an error response."""
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self._send_cors_headers()
        self.end_headers()
        error_body = json.dumps({"error": {"message": message, "code": code}})
        self.wfile.write(error_body.encode())

    def _send_stats(self):
        """Send rate limiter stats."""
        stats = self.rate_limiter.stats()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps(stats, indent=2).encode())


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """Threaded HTTP server for handling concurrent connections."""
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description='LLM Rate Limiter Proxy')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT,
                        help=f'Port to listen on (default: {DEFAULT_PORT})')
    parser.add_argument('--backend', type=str, default=DEFAULT_BACKEND,
                        help=f'Backend URL (default: {DEFAULT_BACKEND})')
    parser.add_argument('--max-concurrent', type=int, default=DEFAULT_MAX_CONCURRENT,
                        help=f'Max concurrent requests (default: {DEFAULT_MAX_CONCURRENT})')
    parser.add_argument('--queue-size', type=int, default=DEFAULT_QUEUE_SIZE,
                        help=f'Max queued requests (default: {DEFAULT_QUEUE_SIZE})')
    args = parser.parse_args()

    # Configure the handler
    ProxyHandler.backend_url = args.backend
    ProxyHandler.rate_limiter = RateLimiter(args.max_concurrent, args.queue_size)

    # Start the server
    server = ThreadedHTTPServer(('0.0.0.0', args.port), ProxyHandler)

    logger.info("=" * 60)
    logger.info("LLM Rate Limiter Proxy")
    logger.info("=" * 60)
    logger.info(f"Listening on: http://0.0.0.0:{args.port}")
    logger.info(f"Backend: {args.backend}")
    logger.info(f"Max concurrent requests: {args.max_concurrent}")
    logger.info(f"Queue size: {args.queue_size}")
    logger.info(f"Stats endpoint: http://localhost:{args.port}/proxy/stats")
    logger.info("=" * 60)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
