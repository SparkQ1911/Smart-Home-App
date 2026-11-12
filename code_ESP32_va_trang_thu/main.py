# ESP32 thật: 4 ngõ ra GPIO, một cảm biến DHT22 và MQTT bridge.
import network
import ntptime
import ssl
import time
import dht
from machine import Pin
from umqtt.simple import MQTTClient
from machine_config import (
    MQTT_HOST,
    MQTT_CA_CERT,
    MQTT_PASSWORD,
    MQTT_PORT,
    MQTT_USERNAME,
    OUTPUT_ACTIVE_LEVEL,
    WIFI_PASS,
    WIFI_SSID,
)

GOC = MQTT_USERNAME + "/f/"
CLIENT_ID = "esp32-giang06-nhatm-" + str(time.ticks_ms())

if OUTPUT_ACTIVE_LEVEL not in (0, 1):
    raise ValueError("OUTPUT_ACTIVE_LEVEL phải là 0 hoặc 1")
OUTPUT_OFF_LEVEL = 1 - OUTPUT_ACTIVE_LEVEL

# Ngõ ra được khởi tạo ở trạng thái OFF; sơ đồ đèn LED dùng active-high.
THIET_BI = {
    "den_khach": Pin(22, Pin.OUT, value=OUTPUT_OFF_LEVEL),
    "quat":      Pin(23, Pin.OUT, value=OUTPUT_OFF_LEVEL),
    "den_ngu":   Pin(18, Pin.OUT, value=OUTPUT_OFF_LEVEL),
    "den_tam":   Pin(17, Pin.OUT, value=OUTPUT_OFF_LEVEL),
}
COMMAND_FEEDS = {
    "den_khach": "yellow-command",
    "quat": "blue-command",
    "den_ngu": "green-command",
    "den_tam": "red-command",
}
STATE_FEEDS = {
    "den_khach": "yellow-state",
    "quat": "blue-state",
    "den_ngu": "green-state",
    "den_tam": "red-state",
}
cam_bien = dht.DHT22(Pin(15))

che_do = "TAY"     # TAY = nguoi dung bam | TUDONG = quat tu chay theo nhiet do
nguong = 30.0      # do C: nong hon thi bat quat
client = None
lan_doc_cuoi = 0
lan_gui_mqtt_cuoi = time.ticks_ms() - 1100


def ket_noi_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    if not wlan.isconnected():
        print("Dang ket noi WiFi", end="")
        wlan.connect(WIFI_SSID, WIFI_PASS)
        while not wlan.isconnected():
            time.sleep(0.3)
            print(".", end="")
    print(" OK, IP:", wlan.ifconfig()[0])


def dat_thiet_bi(ten, bat):
    THIET_BI[ten].value(OUTPUT_ACTIVE_LEVEL if bat else OUTPUT_OFF_LEVEL)
    bao_trang_thai(ten)


def bao_trang_thai(ten):
    bat = THIET_BI[ten].value() == OUTPUT_ACTIVE_LEVEL
    trang_thai = "ON" if bat else "OFF"
    print(ten, "->", trang_thai)
    if client:
        gui_mqtt(STATE_FEEDS[ten], trang_thai)


def gui_mqtt(feed, payload):
    global lan_gui_mqtt_cuoi
    elapsed = time.ticks_diff(time.ticks_ms(), lan_gui_mqtt_cuoi)
    if elapsed < 1100:
        time.sleep_ms(1100 - elapsed)
    client.publish((GOC + feed).encode(), str(payload).encode(), qos=1)
    lan_gui_mqtt_cuoi = time.ticks_ms()


def nhan_tin(topic, msg):
    global lan_gui_mqtt_cuoi
    t = topic.decode()
    nd = msg.decode().strip()
    for ten in THIET_BI:
        if t == GOC + COMMAND_FEEDS[ten]:
            if ten == "quat" and che_do == "TUDONG":
                print("Che do TUDONG: bo qua lenh tay cua quat")
                return
            if nd.upper() in ("ON", "OFF"):
                lan_gui_mqtt_cuoi = time.ticks_ms()
                dat_thiet_bi(ten, nd.upper() == "ON")
            return


def ket_noi_mqtt():
    if not MQTT_CA_CERT.strip():
        raise ValueError("Phải cấu hình MQTT_CA_CERT để xác thực TLS broker")
    ntptime.settime()
    c = MQTTClient(
        CLIENT_ID,
        MQTT_HOST,
        port=MQTT_PORT,
        user=MQTT_USERNAME,
        password=MQTT_PASSWORD,
        keepalive=30,
        ssl=True,
        ssl_params={
            "server_hostname": MQTT_HOST,
            "cert_reqs": ssl.CERT_REQUIRED,
            "cadata": MQTT_CA_CERT,
        },
    )
    c.set_callback(nhan_tin)
    print("Dang ket noi Cloud MQTT... ", end="")
    c.connect()
    print("OK")
    for ten in THIET_BI:
        c.subscribe((GOC + COMMAND_FEEDS[ten]).encode(), qos=1)
    print("Da subscribe cac Adafruit IO command feeds.")
    return c


def doc_cam_bien_va_xu_ly():
    try:
        cam_bien.measure()
        t = cam_bien.temperature()
        h = cam_bien.humidity()
    except OSError:
        print("Khong doc duoc DHT22")
        return
    gui_mqtt("sensor-temperature", "%.2f" % t)
    gui_mqtt("sensor-humidity", "%.2f" % h)
    print("Cam bien: %.1f C, %.1f %%" % (t, h))
    if che_do == "TUDONG":
        dang_bat = THIET_BI["quat"].value() == OUTPUT_ACTIVE_LEVEL
        if t > nguong and not dang_bat:
            dat_thiet_bi("quat", True)
        elif t < nguong - 1 and dang_bat:
            dat_thiet_bi("quat", False)


ket_noi_wifi()
thoi_gian_cho_ket_noi_lai = 5
while True:
    try:
        if client is None:
            client = ket_noi_mqtt()
            thoi_gian_cho_ket_noi_lai = 5
            for ten in THIET_BI:
                bao_trang_thai(ten)
        client.check_msg()
        if time.ticks_diff(time.ticks_ms(), lan_doc_cuoi) > 10000:
            lan_doc_cuoi = time.ticks_ms()
            doc_cam_bien_va_xu_ly()
        time.sleep(0.1)
    except Exception as e:
        print("Mat ket noi:", e, "- thu lai sau", thoi_gian_cho_ket_noi_lai, "s")
        client = None
        time.sleep(thoi_gian_cho_ket_noi_lai)
        thoi_gian_cho_ket_noi_lai = min(thoi_gian_cho_ket_noi_lai * 2, 60)
        ket_noi_wifi()
