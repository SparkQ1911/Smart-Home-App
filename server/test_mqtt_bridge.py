import unittest
from types import SimpleNamespace

from server.mqtt_bridge import MqttBridge
from server.smart_home_server import SmartHomeStore


class FakeMQTTClient:
    def __init__(self):
        self.published = []
        self.subscriptions = []
        self.connected_to = None

    def username_pw_set(self, username, password):
        self.credentials = (username, password)

    def tls_set(self):
        self.tls_enabled = True

    def connect_async(self, host, port, keepalive):
        self.connected_to = (host, port, keepalive)

    def loop_start(self):
        pass

    def loop_stop(self):
        pass

    def disconnect(self):
        pass

    def subscribe(self, topics):
        self.subscriptions.extend(topics)

    def publish(self, topic, payload, qos, retain):
        self.published.append((topic, payload, qos, retain))
        return SimpleNamespace(rc=0)


class MQTTBridgeTests(unittest.TestCase):
    def setUp(self):
        self.store = SmartHomeStore()
        self.client = FakeMQTTClient()
        self.bridge = MqttBridge(
            self.store,
            host="io.adafruit.com",
            username="adafruit-user",
            password="test-password",
            client=self.client,
        )

    def test_connects_with_tls_and_subscribes_to_sensor_and_state_topics(self):
        self.bridge.start()
        self.client.on_connect(self.client, None, None, 0, None)

        self.assertTrue(self.client.tls_enabled)
        self.assertEqual(self.client.connected_to, ("io.adafruit.com", 8883, 60))
        self.assertTrue(self.bridge.connected.is_set())
        self.assertEqual(
            {topic for topic, qos in self.client.subscriptions},
            {
                "adafruit-user/f/sensor-temperature",
                "adafruit-user/f/sensor-humidity",
                "adafruit-user/f/yellow-state",
                "adafruit-user/f/blue-state",
                "adafruit-user/f/green-state",
                "adafruit-user/f/red-state",
            },
        )

    def test_publishes_app_commands_without_retaining_them(self):
        self.bridge.connected.set()

        self.bridge.publish_command("blue", "ON")

        self.assertEqual(
            self.client.published,
            [("adafruit-user/f/blue-command", "ON", 1, False)],
        )

    def test_device_report_completes_only_matching_pending_command(self):
        command = self.store.enqueue_device_command("yellow", "OFF")

        self.bridge._handle_device_state("yellow", b"ON")
        self.assertEqual(
            self.store.get_device_command("yellow", command["id"])["status"],
            "pending",
        )

        self.bridge._handle_device_state("yellow", b"OFF")
        self.assertEqual(
            self.store.get_device_command("yellow", command["id"])["status"],
            "completed",
        )
        self.assertEqual(self.store.get_device("yellow")["status"], "OFF")

    def test_sensor_payload_updates_living_room_reading(self):
        self.bridge._handle_sensor("sensor-temperature", b"28.5")
        self.bridge._handle_sensor("sensor-humidity", b"63")

        reading = self.store.get_latest_sensors()
        self.assertEqual(reading["rooms"][0]["room"], "Phòng khách")
        self.assertEqual(reading["rooms"][0]["temperature"], 28.5)
        self.assertEqual(reading["rooms"][0]["humidity"], 63)

    def test_rejects_non_finite_sensor_values(self):
        with self.assertRaises(ValueError):
            self.bridge._handle_sensor("sensor-temperature", b"NaN")

    def test_routes_incoming_feed_values(self):
        self.bridge._on_message(
            self.client,
            None,
            SimpleNamespace(
                topic="adafruit-user/f/sensor-temperature",
                payload=b"27.5",
            ),
        )
        self.bridge._on_message(
            self.client,
            None,
            SimpleNamespace(
                topic="adafruit-user/f/sensor-humidity",
                payload=b"55",
            ),
        )

        self.assertEqual(
            self.store.get_latest_sensors()["rooms"][0]["temperature"],
            27.5,
        )


if __name__ == "__main__":
    unittest.main()
