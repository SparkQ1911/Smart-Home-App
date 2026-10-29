#include <DHTesp.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

namespace {

constexpr char kWifiSsid[] = "Wokwi-GUEST";
constexpr char kWifiPassword[] = "";
constexpr char kServerUrl[] =
    "https://smart-home-demo-api.onrender.com/api/simulator/publish";
constexpr unsigned long kPublishIntervalMs = 5000;

struct RoomSensor {
  const char* room;
  uint8_t pin;
  DHTesp* sensor;
};

DHTesp livingRoomDht;
DHTesp kitchenDht;
DHTesp bedroomDht;
DHTesp bathroomDht;

RoomSensor sensors[] = {
    {"Phòng khách", 15, &livingRoomDht},
    {"Nhà bếp", 4, &kitchenDht},
    {"Phòng ngủ", 5, &bedroomDht},
    {"Phòng tắm", 18, &bathroomDht},
};

unsigned long lastPublishedAt = 0;

bool connectToWifi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.print("Connecting to Wokwi WiFi");
  WiFi.begin(kWifiSsid, kWifiPassword, 6);
  for (int attempt = 0; attempt < 60 && WiFi.status() != WL_CONNECTED;
       ++attempt) {
    delay(250);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi connection failed; will retry.");
    return false;
  }

  Serial.print("Connected, ESP32 IP: ");
  Serial.println(WiFi.localIP());
  return true;
}

bool appendReading(String& json, const RoomSensor& sensor) {
  const TempAndHumidity reading = sensor.sensor->getTempAndHumidity();
  if (isnan(reading.temperature) || isnan(reading.humidity)) {
    Serial.printf("Could not read DHT22 in %s; skipping publish.\n",
                  sensor.room);
    return false;
  }

  if (json[json.length() - 1] != '[') json += ',';
  json += "{\"room\":\"";
  json += sensor.room;
  json += "\",\"temperature\":";
  json += String(reading.temperature, 1);
  json += ",\"humidity\":";
  json += String(reading.humidity, 1);
  json += '}';
  Serial.printf("%s: %.1f C, %.1f %%\n", sensor.room, reading.temperature,
                reading.humidity);
  return true;
}

void publishReadings() {
  if (!connectToWifi()) return;

  String payload = "{\"rooms\":[";
  for (const RoomSensor& sensor : sensors) {
    if (!appendReading(payload, sensor)) return;
  }
  payload += "]}";

  WiFiClientSecure client;
  // Only for the non-sensitive Wokwi demo data.
  client.setInsecure();
  HTTPClient request;
  if (!request.begin(client, kServerUrl)) {
    Serial.println("Could not create HTTP request.");
    return;
  }
  request.addHeader("Content-Type", "application/json");
  const int status = request.POST(payload);
  const String response = request.getString();
  request.end();

  Serial.printf("Server response: HTTP %d %s\n", status, response.c_str());
  if (status != 202) {
    Serial.println("Publish failed; check the public server URL.");
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  for (RoomSensor& sensor : sensors) {
    sensor.sensor->setup(sensor.pin, DHTesp::DHT22);
  }
  connectToWifi();
  publishReadings();
  lastPublishedAt = millis();
}

void loop() {
  if (millis() - lastPublishedAt >= kPublishIntervalMs) {
    lastPublishedAt = millis();
    publishReadings();
  }
  delay(50);
}
