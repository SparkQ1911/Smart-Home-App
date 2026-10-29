import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server.smart_home_server import create_server


class SmartHomeServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = create_server("127.0.0.1", 0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def request_json(self, method, path, payload=None):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            self.base_url + path,
            data=body,
            headers={"Content-Type": "application/json"},
            method=method,
        )
        with urlopen(request, timeout=2) as response:
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
            "POST", "/api/simulator/publish", reading
        )
        self.assertEqual(status, 202)
        self.assertEqual(result["rooms"], 2)

        status, result = self.request_json("GET", "/api/sensors/latest")
        self.assertEqual(status, 200)
        self.assertEqual(result["rooms"][0]["room"], "Nhà bếp")
        self.assertEqual(result["rooms"][0]["temperature"], 29.5)

    def test_device_control_is_confirmed_and_recorded(self):
        status, result = self.request_json(
            "POST", "/api/devices/living-light/control", {"state": "OFF"}
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "OFF")

        _, status_result = self.request_json(
            "GET", "/api/devices/living-light/status"
        )
        self.assertEqual(status_result["status"], "OFF")
        _, history = self.request_json("GET", "/api/history")
        self.assertEqual(history["history"][0]["action"], "turned_off")

    def test_invalid_sensor_payload_is_rejected(self):
        try:
            with self.assertRaises(HTTPError) as caught:
                self.request_json(
                    "POST",
                    "/api/simulator/publish",
                    {"rooms": [{"room": "Nhà bếp", "temperature": "nóng"}]},
                )
            self.assertEqual(caught.exception.code, 400)
        finally:
            if "caught" in locals():
                caught.exception.close()


if __name__ == "__main__":
    unittest.main()
