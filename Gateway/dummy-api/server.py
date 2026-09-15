import json
import os
import signal
import socket
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_NAME = os.environ.get("SERVICE_NAME", "api")
PORT = int(os.environ.get("SERVICE_PORT", "8080"))
CONSUL = os.environ.get("CONSUL_HTTP_ADDR", "http://consul:8500")
HOSTNAME = socket.gethostname()


def my_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return socket.gethostbyname(HOSTNAME)
    finally:
        s.close()


IP = my_ip()
SERVICE_ID = f"{SERVICE_NAME}-{HOSTNAME}"


def consul(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        CONSUL + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return resp.status


def register():
    payload = {
        "ID": SERVICE_ID,
        "Name": SERVICE_NAME,
        "Address": IP,
        "Port": PORT,
        "Tags": ["gateway-demo"],
        "Check": {
            "HTTP": f"http://{IP}:{PORT}/health",
            "Interval": "5s",
            "Timeout": "2s",
            "DeregisterCriticalServiceAfter": "30s",
        },
    }
    for attempt in range(60):
        try:
            consul("PUT", "/v1/agent/service/register", payload)
            print(f"[{SERVICE_ID}] registered at {IP}:{PORT}", flush=True)
            return
        except Exception as exc:
            print(f"[{SERVICE_ID}] register retry {attempt}: {exc}", flush=True)
            time.sleep(2)


def deregister():
    try:
        consul("PUT", f"/v1/agent/service/deregister/{SERVICE_ID}")
        print(f"[{SERVICE_ID}] deregistered", flush=True)
    except Exception as exc:
        print(f"[{SERVICE_ID}] deregister failed: {exc}", flush=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "dummy-api"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _info(self, body=None):
        return {
            "service": SERVICE_NAME,
            "instance": HOSTNAME,
            "ip": IP,
            "method": self.command,
            "path": self.path,
            "body": body,
        }

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"status": "ok", "instance": HOSTNAME})
        if self.path.startswith("/fail"):
            return self._send(500, {"error": "simulated failure", "instance": HOSTNAME})
        return self._send(200, self._info())

    def do_POST(self):
        return self._echo()

    def do_PUT(self):
        return self._echo()

    def do_DELETE(self):
        return self._echo()

    def do_PATCH(self):
        return self._echo()

    def _echo(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        parsed = None
        if raw:
            try:
                parsed = json.loads(raw)
            except ValueError:
                parsed = raw.decode(errors="replace")
        return self._send(200, self._info(parsed))

    def log_message(self, fmt, *args):
        print(f"[{HOSTNAME}] {fmt % args}", flush=True)


def main():
    if os.environ.get("SKIP_REGISTER") != "1":
        threading.Thread(target=register, daemon=True).start()

    def shutdown(_signum, _frame):
        deregister()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
