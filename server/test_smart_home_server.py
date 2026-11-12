import json
import threading
import unittest
import uuid
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server.smart_home_server import (
    MySQLStore,
    SmartHomeStore,
    create_server,
)


class SmartHomeServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = create_server(
            "127.0.0.1",
            0,
            auth_secret="test-secret-with-more-than-thirty-two-characters",
            device_key="test-device-key-with-more-than-thirty-two-characters",
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def setUp(self):
        _, result = self.request_json(
            "POST",
            "/api/auth/register",
            {"name": "Test User", "email": f"{uuid.uuid4()}@example.com", "password": "valid-pass-123"},
        )
        self.token = result["token"]

    def request_json(self, method, path, payload=None, token=None, device=False):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if device:
            headers["X-Device-Key"] = (
                "test-device-key-with-more-than-thirty-two-characters"
            )
        request = Request(
            self.base_url + path,
            data=body,
            headers=headers,
            method=method,
        )
        with urlopen(request, timeout=10) as response:
            return response.status, json.loads(response.read().decode("utf-8"))

    def test_simulator_data_is_returned_by_sensor_api(self):
        reading = {
            "updatedAt": "2026-10-28T10:00:00+00:00",
            "rooms": [
                {"room": "Nhà bếp", "temperature": 29.5, "humidity": 60},
                {"room": "Phòng khách", "temperature": 27.0, "humidity": 62},
            ],
        }
        status, result = self.request_json(
            "POST", "/api/simulator/publish", reading, device=True
        )
        self.assertEqual(status, 202)
        self.assertEqual(result["rooms"], 2)

        status, result = self.request_json(
            "GET", "/api/sensors/latest", token=self.token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["rooms"][0]["room"], "Nhà bếp")
        self.assertEqual(result["rooms"][0]["temperature"], 29.5)

    def test_device_command_round_trip_through_iot_and_app(self):
        status, result = self.request_json(
            "POST",
            "/api/devices/yellow/control",
            {"state": "OFF"},
            self.token,
        )
        self.assertEqual(status, 202)
        self.assertEqual(result["status"], "pending")
        command_id = result["commandId"]

        _, command = self.request_json(
            "GET",
            "/api/iot/devices/yellow/commands/pending",
            device=True,
        )
        self.assertEqual(command["commandId"], command_id)
        self.assertEqual(command["state"], "OFF")
        _, devices_before_ack = self.request_json(
            "GET", "/api/devices", token=self.token
        )
        self.assertEqual(devices_before_ack["devices"][0]["status"], "ON")

        _, report = self.request_json(
            "POST",
            "/api/iot/devices/yellow/state",
            {"commandId": command_id, "state": "OFF"},
            device=True,
        )
        self.assertEqual(report["status"], "OFF")
        _, command_status = self.request_json(
            "GET",
            f"/api/devices/yellow/commands/{command_id}",
            token=self.token,
        )
        self.assertEqual(command_status["status"], "completed")
        self.assertEqual(command_status["reportedState"], "OFF")

        _, status_result = self.request_json(
            "GET", "/api/devices/yellow/status", token=self.token
        )
        self.assertEqual(status_result["status"], "OFF")
        _, history = self.request_json(
            "GET", "/api/history", token=self.token
        )
        self.assertEqual(history["history"][0]["action"], "reported_off")

    def test_invalid_sensor_payload_is_rejected(self):
        try:
            with self.assertRaises(HTTPError) as caught:
                self.request_json(
                    "POST",
                    "/api/simulator/publish",
                    {"rooms": [{"room": "Nhà bếp", "temperature": "nóng"}]},
                    device=True,
                )
            self.assertEqual(caught.exception.code, 400)
        finally:
            if "caught" in locals():
                caught.exception.close()

    def test_mysql_sensor_timestamps_are_normalized_to_utc(self):
        stored = MySQLStore._parse_database_time("2026-10-29T08:00:00+03:00")
        self.assertEqual(stored.isoformat(), "2026-10-29T05:00:00")

    def test_in_memory_store_remains_available_for_api_tests(self):
        store = SmartHomeStore()
        self.assertEqual(store.health()["storage"], "memory")
        self.assertEqual(store.list_devices()[0]["id"], "yellow")

    def test_device_list_shows_rooms_without_gpio_pins(self):
        _, result = self.request_json(
            "GET", "/api/devices", token=self.token
        )
        devices = result["devices"]
        self.assertEqual(
            {device["id"] for device in devices},
            {"yellow", "green", "red", "blue"},
        )
        rooms = {device["id"]: device["room"] for device in devices}
        self.assertEqual(rooms["red"], "Phòng tắm")
        self.assertEqual(rooms["green"], "Phòng ngủ")
        self.assertEqual(rooms["yellow"], "Phòng khách")
        self.assertTrue(
            all("gpio" not in device and "pin" not in device for device in devices)
        )

    def test_device_routes_reject_missing_device_key(self):
        with self.assertRaises(HTTPError) as unauthorized:
            self.request_json(
                "GET",
                "/api/iot/devices/yellow/commands/pending",
            )
        self.assertEqual(unauthorized.exception.code, 401)
        unauthorized.exception.close()

    def test_device_mismatch_marks_command_failed_and_blocks_second_pending(self):
        _, command = self.request_json(
            "POST",
            "/api/devices/blue/control",
            {"state": "ON"},
            self.token,
        )
        with self.assertRaises(HTTPError) as duplicate:
            self.request_json(
                "POST",
                "/api/devices/blue/control",
                {"state": "OFF"},
                self.token,
            )
        self.assertEqual(duplicate.exception.code, 409)
        duplicate.exception.close()

        self.request_json(
            "POST",
            "/api/iot/devices/blue/state",
            {"commandId": command["commandId"], "state": "OFF"},
            device=True,
        )
        _, result = self.request_json(
            "GET",
            f"/api/devices/blue/commands/{command['commandId']}",
            token=self.token,
        )
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["reportedState"], "OFF")

    def test_account_registration_login_and_account_deletion(self):
        email = f"{uuid.uuid4()}@example.com"
        payload = {
            "name": "Mina",
            "email": email,
            "password": "safe-password-123",
        }
        _, registration = self.request_json(
            "POST", "/api/auth/register", payload
        )
        self.assertEqual(registration["user"]["email"], email)
        self.assertNotIn("passwordHash", registration["user"])
        with self.assertRaises(HTTPError) as duplicate:
            self.request_json("POST", "/api/auth/register", payload)
        self.assertEqual(duplicate.exception.code, 409)
        duplicate.exception.close()

        _, login = self.request_json(
            "POST",
            "/api/auth/login",
            {"email": email.upper(), "password": payload["password"]},
        )
        _, profile = self.request_json(
            "GET", "/api/auth/me", token=login["token"]
        )
        self.assertEqual(profile["user"]["name"], "Mina")

        with self.assertRaises(HTTPError) as wrong_password:
            self.request_json(
                "DELETE",
                "/api/auth/me",
                {"password": "incorrect-password"},
                login["token"],
            )
        self.assertEqual(wrong_password.exception.code, 401)
        wrong_password.exception.close()
        self.request_json("GET", "/api/auth/me", token=login["token"])

        request = Request(
            self.base_url + "/api/auth/me",
            data=json.dumps({"password": "safe-password-123"}).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {login['token']}",
                "Content-Type": "application/json",
            },
            method="DELETE",
        )
        with urlopen(request, timeout=2) as response:
            self.assertEqual(response.status, 200)
        with self.assertRaises(HTTPError) as deleted:
            self.request_json("GET", "/api/auth/me", token=login["token"])
        self.assertEqual(deleted.exception.code, 401)
        deleted.exception.close()

    def test_data_routes_require_authentication(self):
        with self.assertRaises(HTTPError) as unauthorized:
            self.request_json("GET", "/api/devices")
        self.assertEqual(unauthorized.exception.code, 401)
        unauthorized.exception.close()
        with self.assertRaises(HTTPError) as control_unauthorized:
            self.request_json(
                "POST",
                "/api/devices/yellow/control",
                {"state": "OFF"},
            )
        self.assertEqual(control_unauthorized.exception.code, 401)
        control_unauthorized.exception.close()


if __name__ == "__main__":
    unittest.main()
