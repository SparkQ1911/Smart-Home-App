import math
import os
import threading
import time

from mysql.connector import Error as MySQLError


DEVICE_TOPICS = {
    "yellow": ("yellow-command", "yellow-state"),
    "blue": ("blue-command", "blue-state"),
    "green": ("green-command", "green-state"),
    "red": ("red-command", "red-state"),
}
TEMPERATURE_FEED = "sensor-temperature"
HUMIDITY_FEED = "sensor-humidity"


class BridgeUnavailableError(RuntimeError):
    pass


class MqttBridge:
    def __init__(
        self,
        store,
        host,
        username,
        password,
        port=8883,
        client=None,
    ):
        if not host or not username or not password:
            raise ValueError("MQTT_HOST, MQTT_USERNAME và MQTT_PASSWORD là bắt buộc.")
        self.store = store
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.topic_prefix = f"{username}/f/"
        self.connected = threading.Event()
        self._sensor_values = {}
        self._received_sensor_feeds = set()
        self._lock = threading.Lock()
        self._command_publish_lock = threading.Lock()
        self._last_command_published_at = 0.0

        if client is None:
            try:
                import paho.mqtt.client as mqtt
            except ImportError as error:
                raise RuntimeError("Cài paho-mqtt để bật MQTT bridge.") from error
            client = mqtt.Client(
                mqtt.CallbackAPIVersion.VERSION2,
                client_id="smart-home-api-bridge",
            )
        self.client = client
        self.client.username_pw_set(username, password)
        self.client.tls_set()
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message

    @classmethod
    def from_environment(cls, store):
        username = os.environ.get("MQTT_USERNAME", "").strip()
        password = os.environ.get("MQTT_PASSWORD", "")
        if not username and not password:
            return None
        if not username or not password:
            raise ValueError(
                "MQTT_USERNAME và MQTT_PASSWORD phải được cấu hình cùng nhau."
            )
        return cls(
            store=store,
            host=os.environ.get("MQTT_HOST", "").strip() or "io.adafruit.com",
            port=int(os.environ.get("MQTT_PORT", "8883")),
            username=username,
            password=password,
        )

    def start(self):
        self.client.connect_async(self.host, self.port, keepalive=60)
        self.client.loop_start()

    def stop(self):
        self.client.loop_stop()
        self.client.disconnect()

    def publish_command(self, device_id, state):
        topic_name = DEVICE_TOPICS.get(device_id)
        if topic_name is None:
            raise ValueError("Không tìm thấy thiết bị.")
        if not self.connected.is_set():
            raise BridgeUnavailableError("MQTT broker chưa kết nối.")
        with self._command_publish_lock:
            elapsed = time.monotonic() - self._last_command_published_at
            if elapsed < 1.1:
                time.sleep(1.1 - elapsed)
            result = self.client.publish(
                self._feed_topic(topic_name[0]),
                state,
                qos=1,
                retain=False,
            )
            if result.rc == 0:
                self._last_command_published_at = time.monotonic()
        if result.rc != 0:
            raise BridgeUnavailableError("Không gửi được lệnh tới MQTT broker.")

    def _on_connect(self, client, userdata, flags, reason_code, properties=None):
        if int(reason_code) != 0:
            print(f"MQTT connection rejected: {reason_code}", flush=True)
            self.connected.clear()
            return

        with self._lock:
            self._received_sensor_feeds.clear()
        topics = [
            (self._feed_topic(TEMPERATURE_FEED), 1),
            (self._feed_topic(HUMIDITY_FEED), 1),
        ]
        topics.extend(
            (self._feed_topic(feeds[1]), 1)
            for feeds in DEVICE_TOPICS.values()
        )
        client.subscribe(topics)
        self.connected.set()
        print("MQTT bridge connected with TLS.", flush=True)

    def _on_disconnect(
        self, client, userdata, disconnect_flags, reason_code, properties=None
    ):
        self.connected.clear()
        with self._lock:
            self._received_sensor_feeds.clear()
        if int(reason_code) != 0:
            print(f"MQTT connection lost: {reason_code}", flush=True)

    def _on_message(self, client, userdata, message):
        try:
            feed = message.topic.removeprefix(self.topic_prefix)
            if feed in {TEMPERATURE_FEED, HUMIDITY_FEED}:
                self._handle_sensor(feed, message.payload)
                return
            device_id = next(
                (
                    device_id
                    for device_id, feeds in DEVICE_TOPICS.items()
                    if feed == feeds[1]
                ),
                None,
            )
            if device_id is not None:
                self._handle_device_state(device_id, message.payload)
                return
        except (UnicodeDecodeError, ValueError) as error:
            print(
                f"Ignored invalid MQTT message on {message.topic}: {error}",
                flush=True,
            )
        except MySQLError as error:
            print(
                f"Could not process MQTT message on {message.topic}: {error}",
                flush=True,
            )

    def _handle_sensor(self, feed, payload):
        value = self._finite_number(
            float(payload.decode("utf-8")),
            feed,
        )
        with self._lock:
            self._sensor_values[feed] = value
            self._received_sensor_feeds.add(feed)
            if len(self._received_sensor_feeds) < 2:
                return
            temperature = self._sensor_values[TEMPERATURE_FEED]
            humidity = self._sensor_values[HUMIDITY_FEED]
            self._received_sensor_feeds.clear()
        self.store.publish_sensors(
            [
                {
                    "room": "Phòng khách",
                    "temperature": temperature,
                    "humidity": humidity,
                }
            ],
            self._now_iso(),
        )

    def _handle_device_state(self, device_id, payload):
        state = payload.decode("utf-8").strip().upper()
        if state not in {"ON", "OFF"}:
            raise ValueError("Device state must be ON or OFF.")
        pending = self.store.get_pending_device_command(device_id)
        command_id = (
            pending["id"]
            if pending is not None and pending["desiredState"] == state
            else None
        )
        self.store.report_device_state(device_id, state, command_id)

    def _feed_topic(self, feed):
        return f"{self.topic_prefix}{feed}"

    @staticmethod
    def _finite_number(value, field):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{field} must be a number.")
        if not math.isfinite(value):
            raise ValueError(f"{field} must be finite.")
        return value

    @staticmethod
    def _now_iso():
        from datetime import datetime, timezone

        return datetime.now(timezone.utc).isoformat(timespec="seconds")
