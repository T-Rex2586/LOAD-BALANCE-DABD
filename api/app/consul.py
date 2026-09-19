import json
import logging
import os
import socket
import threading
import time
import urllib.request

logger = logging.getLogger("kantin.api.consul")

CONSUL_HTTP_ADDR = os.getenv("CONSUL_HTTP_ADDR", "http://consul:8500")
SERVICE_NAME = os.getenv("SERVICE_NAME", "api")
SERVICE_PORT = int(os.getenv("APP_PORT", "8000"))
ENABLED = os.getenv("CONSUL_ENABLED", "1").lower() not in ("0", "false", "no")
HOSTNAME = socket.gethostname()


def _service_ip() -> str:
    try:
        return socket.gethostbyname(HOSTNAME)
    except OSError:
        return "127.0.0.1"


IP = _service_ip()
SERVICE_ID = f"{SERVICE_NAME}-{IP}-{SERVICE_PORT}"

_started = False


def _request(method: str, path: str, payload: dict | None = None) -> int:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        CONSUL_HTTP_ADDR + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        return response.status


def _register() -> None:
    payload = {
        "ID": SERVICE_ID,
        "Name": SERVICE_NAME,
        "Address": IP,
        "Port": SERVICE_PORT,
        "Tags": ["gateway"],
        "Check": {
            "HTTP": f"http://{IP}:{SERVICE_PORT}/health",
            "Interval": "30s",
            "Timeout": "3s",
            "DeregisterCriticalServiceAfter": "1m",
        },
    }

    for attempt in range(1, 31):
        try:
            _request("PUT", "/v1/agent/service/register", payload)
            logger.info("Consul: terdaftar sebagai %s (%s:%s)", SERVICE_ID, IP, SERVICE_PORT)
            return
        except Exception as exc:  # noqa: BLE001
            logger.warning("Consul: registrasi gagal (%s/30): %s", attempt, exc)
            time.sleep(2)


def _deregister() -> None:
    try:
        _request("PUT", f"/v1/agent/service/deregister/{SERVICE_ID}")
        logger.info("Consul: deregister %s", SERVICE_ID)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Consul: deregister gagal: %s", exc)


def start() -> None:
    global _started
    if not ENABLED or _started:
        return
    _started = True
    threading.Thread(target=_register, name="consul-register", daemon=True).start()


def stop() -> None:
    if ENABLED:
        _deregister()
