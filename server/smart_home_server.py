import json
import math
import os
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class SmartHomeStore:
    def __init__(self):
        self.lock = threading.Lock()
        self.devices = [
            {
                "id": "living-light",
                "name": "Đèn phòng khách",
                "type": "light",
                "status": "ON",
                "room": "Phòng khách",
            },
            {
                "id": "kitchen-fan",
                "name": "Quạt thông gió",
                "type": "fan",
                "status": "OFF",
                "room": "Nhà bếp",
            },
            {
                "id": "bedroom-ac",
                "name": "Điều hòa phòng ngủ",
                "type": "air_conditioner",
                "status": "OFF",
                "room": "Phòng ngủ",
            },
            {
                "id": "bathroom-light",
                "name": "Đèn phòng tắm",
                "type": "light",
                "status": "OFF",
                "room": "Phòng tắm",
            },
        ]
        self.rooms = []
        self.updated_at = None
        self.history = []

    def record(self, action, device=None, details=None):
        self.history.insert(
            0,
            {
                "id": f"{int(datetime.now().timestamp() * 1000)}-{len(self.history)}",
                "deviceId": device["id"] if device else None,
                "deviceName": device["name"] if device else None,
                "action": action,
                "details": details or {},
                "createdAt": now_iso(),
            },
        )
        del self.history[100:]


def create_server(host="0.0.0.0", port=8080, store=None):
    store = store or SmartHomeStore()

    class Handler(BaseHTTPRequestHandler):
        server_version = "SmartHomeSimulator/1.0"

        def _send_json(self, status, payload):
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode(
                "utf-8"
            )
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers", "Content-Type, Accept"
            )
            self.end_headers()
            self.wfile.write(body)

        def _read_json(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as error:
                raise ValueError("Content-Length không hợp lệ.") from error
            if length <= 0 or length > 65536:
                raise ValueError("Kích thước JSON phải từ 1 đến 65536 byte.")
            try:
                payload = json.loads(self.rfile.read(length))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ValueError("Request body phải là JSON hợp lệ.") from error
            if not isinstance(payload, dict):
                raise ValueError("Request JSON phải là object.")
            return payload

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers", "Content-Type, Accept"
            )
            self.send_header("Access-Control-Max-Age", "600")
            self.end_headers()

        def do_GET(self):
            path = urlparse(self.path).path.rstrip("/") or "/"
            if path == "/api/health":
                self._send_json(200, {"status": "ok", "server": self.server_version})
                return
            if path == "/api/devices":
                with store.lock:
                    devices = [dict(device) for device in store.devices]
                self._send_json(200, {"devices": devices})
                return
            if path == "/api/sensors/latest":
                with store.lock:
                    payload = {
                        "rooms": [dict(room) for room in store.rooms],
                        "updatedAt": store.updated_at,
                    }
                self._send_json(200, payload)
                return
            if path == "/api/history":
                with store.lock:
                    history = list(store.history)
                self._send_json(200, {"history": history})
                return
            parts = path.split("/")
            if len(parts) == 5 and parts[:3] == ["", "api", "devices"]:
                device_id = unquote(parts[3])
                if parts[4] == "status":
                    with store.lock:
                        device = next(
                            (item for item in store.devices if item["id"] == device_id),
                            None,
                        )
                        if device is None:
                            self._send_json(404, {"error": "Không tìm thấy thiết bị."})
                        else:
                            self._send_json(200, {"status": device["status"]})
                    return
            self._send_json(404, {"error": "Không tìm thấy endpoint."})

        def do_POST(self):
            path = urlparse(self.path).path.rstrip("/")
            try:
                payload = self._read_json()
                if path == "/api/simulator/publish":
                    self._publish(payload)
                    return
                parts = path.split("/")
                if len(parts) == 5 and parts[:3] == ["", "api", "devices"] and parts[4] == "control":
                    self._control(unquote(parts[3]), payload)
                    return
                self._send_json(404, {"error": "Không tìm thấy endpoint."})
            except ValueError as error:
                self._send_json(400, {"error": str(error)})

        def _publish(self, payload):
            rooms = payload.get("rooms")
            if not isinstance(rooms, list) or not rooms:
                raise ValueError("rooms phải là danh sách có ít nhất một phòng.")
            normalized = []
            updated_at = payload.get("updatedAt") or now_iso()
            for room in rooms:
                if not isinstance(room, dict):
                    raise ValueError("Mỗi phòng phải là một JSON object.")
                name = room.get("room") or room.get("area")
                if not isinstance(name, str) or not name.strip():
                    raise ValueError("Mỗi phòng cần có tên room.")
                item = {"room": name.strip(), "updatedAt": updated_at}
                for field in ("temperature", "humidity"):
                    value = room.get(field)
                    if value is not None:
                        if isinstance(value, bool) or not isinstance(value, (int, float)):
                            raise ValueError(f"{field} phải là số.")
                        if not math.isfinite(value):
                            raise ValueError(f"{field} phải là số hữu hạn.")
                        item[field] = value
                for key, value in room.items():
                    if key not in {"room", "area", "temperature", "humidity", "updatedAt"}:
                        item[key] = value
                normalized.append(item)
            with store.lock:
                store.rooms = normalized
                store.updated_at = updated_at
            self._send_json(202, {"accepted": True, "rooms": len(normalized), "updatedAt": updated_at})

        def _control(self, device_id, payload):
            state = payload.get("state", payload.get("status"))
            if isinstance(state, bool):
                state = "ON" if state else "OFF"
            if not isinstance(state, str) or state.upper() not in {"ON", "OFF"}:
                raise ValueError("state phải là ON hoặc OFF.")
            with store.lock:
                device = next(
                    (item for item in store.devices if item["id"] == device_id),
                    None,
                )
                if device is None:
                    self._send_json(404, {"error": "Không tìm thấy thiết bị."})
                    return
                device["status"] = state.upper()
                store.record(f"turned_{state.lower()}", device=device)
                confirmed = device["status"]
            self._send_json(200, {"status": confirmed})

        def log_message(self, fmt, *args):
            print(f"{self.address_string()} - {fmt % args}", flush=True)

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    return Server((host, port), Handler)


def main():
    host = os.environ.get("SMART_HOME_HOST", "0.0.0.0")
    port = int(os.environ.get("SMART_HOME_PORT", os.environ.get("PORT", "8080")))
    server = create_server(host, port)
    print(f"Smart Home API đang nghe tại http://{host}:{port}", flush=True)
    print(
        "Demo API không có xác thực; không dùng với dữ liệu hoặc thiết bị thật.",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nĐang dừng Smart Home API...", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
