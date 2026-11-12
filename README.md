# Smart Home App

Ứng dụng Flutter bằng tiếng Việt để giám sát cảm biến và điều khiển thiết bị
IoT thông qua REST API và MQTT bridge. Người dùng đăng ký/đăng nhập bằng email và mật khẩu;
app tự kết nối API demo công khai
`https://smart-home-demo-api.onrender.com`. Địa chỉ API được cấu hình nội bộ,
không hiển thị trong **Cài đặt**.

## Yêu cầu

- Flutter SDK 3.27 trở lên và Dart SDK 3.6 trở lên.
- Edge/Chrome để chạy thử trên Web; Android Studio/Android SDK hoặc thiết bị
  Android đã bật USB debugging để chạy trên Android.
- Server REST API có thể truy cập từ thiết bị chạy ứng dụng.

## Cài đặt và chạy

Từ thư mục dự án:

```powershell
flutter pub get
flutter run
```

Chạy trên trình duyệt Edge:

```powershell
flutter run -d edge
```

Chạy trên Android: bật USB debugging và kết nối điện thoại, hoặc mở Android
Studio để tạo Android Emulator; sau đó kiểm tra thiết bị và chạy:

```powershell
flutter devices
flutter run -d <device-id>
```

Lần đầu Flutter mới tạo cấu hình Web, có thể thêm nền tảng Web bằng:

```powershell
flutter create --platforms=web .
```

Phân tích mã nguồn:

```powershell
flutter analyze
```

Nếu thư mục `android/` chưa được tạo bởi Flutter SDK, tạo cấu hình nền tảng
Android trước khi chạy:

```powershell
flutter create --platforms=android .
```

## Tài khoản và kết nối API

Màn hình đầu tiên cho phép tạo tài khoản hoặc đăng nhập. Tài khoản được lưu
trong MySQL (`nguoi_dung`); mật khẩu được băm ở server và access token được lưu trong vùng
lưu trữ an toàn của Android. Trong **Cài đặt**, người dùng xem tên/email,
đăng xuất hoặc xóa tài khoản. Xóa tài khoản yêu cầu nhập lại mật khẩu và chỉ
xóa hồ sơ đăng nhập, không xóa dữ liệu cảm biến/thiết bị dùng chung.

API gốc được cấu hình nội bộ qua `SMART_HOME_SERVER_URL` khi build; người dùng
không thể chỉnh sửa nó trong giao diện. Không xóa các endpoint REST mà app và
ESP32 cần để hoạt động. Ví dụ chạy với API local:

```powershell
flutter run --dart-define=SMART_HOME_SERVER_URL=http://192.168.1.10:8080
```

### Server và ESP32 thật qua MQTT

Server mẫu chạy bằng Python 3 và cần cài thư viện trong `server\requirements.txt`.
Bridge dùng [Adafruit IO MQTT](https://io.adafruit.com/api/docs/mqtt) qua TLS.
Tạo tài khoản Adafruit IO, lấy username và AIO Key trong dashboard, rồi tạo
các feed có đúng key sau:

`sensor-temperature`, `sensor-humidity`, `yellow-command`, `yellow-state`,
`blue-command`, `blue-state`, `green-command`, `green-state`, `red-command`,
`red-state`. Adafruit IO free account có giới hạn tốc độ publish theo tài
khoản; xem [tài liệu MQTT chính thức](https://io.adafruit.com/api/docs/mqtt)
để biết giới hạn hiện hành.

```powershell
$env:MQTT_HOST = "io.adafruit.com"
$env:MQTT_PORT = "8883"
$env:MQTT_USERNAME = "<adafruit-io-username>"
$env:MQTT_PASSWORD = "<adafruit-io-key>"
```

Trong Render đặt cùng username và AIO Key vào `MQTT_USERNAME` /
`MQTT_PASSWORD`; blueprint đã đặt host và cổng TLS mặc định. Không commit AIO
Key hoặc chia sẻ nó trong chat. Firmware giãn cách publish và gửi hai số đo
mỗi 10 giây để chừa dung lượng cho lệnh/trạng thái trong giới hạn 30 điểm dữ
liệu mỗi phút của tài khoản miễn phí. Dữ liệu cảm biến chỉ được ghi vào app
sau khi bridge nhận được cả hai feed.

Feed command/state được tách riêng để MQTT echo không tạo vòng lặp. Firmware
ánh xạ `yellow` → LED vàng, `blue` → xanh dương, `green` → xanh lá, `red` →
đỏ; DHT22 được hiển thị trong Phòng khách.
Theo dây bạn xác nhận, GPIO là: LED đỏ/bathroom (`den_tam`) → 17, xanh lá/
bedroom (`den_ngu`) → 18, vàng/living (`den_khach`) → 22, xanh dương/fan
(`quat`) → 23.

Trên ESP32, sao chép `machine_config.py.example` thành `machine_config.py`, điền
Wi-Fi, Adafruit IO username, AIO Key và PEM CA tin cậy có thể xác thực chứng
chỉ của `io.adafruit.com`, rồi tải `main.py` và `machine_config.py` lên board.
Không commit file cấu hình có credentials. Không dùng placeholder hoặc tải
chứng chỉ không kiểm chứng. Firmware đồng bộ thời gian qua NTP và bắt buộc
xác thực chứng chỉ broker khi kết nối TLS tới `io.adafruit.com:8883`; nếu thiếu
CA hoặc không đồng bộ được thời gian thì không kết nối. ESP32 nghe các feed
`*-command` và báo trạng thái qua feed `*-state`. Bridge chỉ xác nhận lệnh khi
nhận trạng thái mong muốn. Trạng thái lệnh chờ được giữ trong RAM và hết hạn
sau 30 giây. Khi lỗi kết nối, firmware tăng dần thời gian chờ thử lại từ 5 lên
tối đa 60 giây để tránh gửi quá nhiều yêu cầu kết nối.

Sơ đồ dây `Hinh_noi_day.png` là bốn đèn LED active-high qua điện trở 220 Ω,
không phải sơ đồ đấu tải điện lưới. Firmware không đổi trạng thái ngõ ra khi
MQTT kết nối lại; khi khởi động, GPIO được khởi tạo OFF theo
`OUTPUT_ACTIVE_LEVEL`. Chỉ đặt `OUTPUT_ACTIVE_LEVEL = 0` nếu đã xác nhận relay
active-low bằng tài liệu/module và thử ở trạng thái không nối tải nguy hiểm.
Không nối đèn/quạt điện lưới trực tiếp vào GPIO; không nạp firmware khi chưa
xác nhận mạch relay, cực tính và nguồn tải.

Server mẫu cần MySQL và các biến xác thực như hướng dẫn bên dưới:

```powershell
cmd /c "mysql -u root -p < tao_csdl.sql"
python -m pip install -r server\requirements.txt
$env:MYSQL_HOST = "127.0.0.1"
$env:MYSQL_PORT = "3306"
$env:MYSQL_DATABASE = "nha_thong_minh"
$env:MYSQL_USER = "root"
$env:MYSQL_PASSWORD = "<mat-khau-mysql>"
$env:SMART_HOME_AUTH_SECRET = (python -c "import secrets; print(secrets.token_urlsafe(32))")
$env:SMART_HOME_DEVICE_KEY = (python -c "import secrets; print(secrets.token_urlsafe(32))")
python server\smart_home_server.py
```

Không đưa mật khẩu SQL hoặc device key vào app Flutter. ESP32 dùng device key
cùng giá trị với server; chỉ server được kết nối trực tiếp MySQL.

Firmware cho ESP32 vật lý nằm trong `code_ESP32_va_trang_thu\main.py`;
`wokwi\` chỉ là tài liệu mô phỏng cũ và không dùng để nạp board thật.
Ứng dụng Flutter vẫn gọi REST API; server nối API với firmware qua MQTT TLS.

### Deploy server demo công khai trên Render Free

Server demo đã được deploy ở gói Free trên Render:
`https://smart-home-demo-api.onrender.com`. Có thể kiểm tra trạng thái tại
`https://smart-home-demo-api.onrender.com/api/health`.

App được cấu hình URL này làm API mặc định; không cần nhập lại trong
**Cài đặt**. Với thiết bị thật, Render cần được cập nhật từ mã nguồn này và
phải cấu hình đủ MySQL, secrets xác thực cùng Adafruit IO trước khi
app/ESP32 hoạt động end-to-end.

**Trạng thái service công khai cần phân biệt:** lần kiểm tra gần nhất, `/api/health`
trả `{"status":"ok","server":"SmartHomeSimulator/1.0"}`,
`/api/sensors/latest` trả `{"rooms":[],"updatedAt":null}` và `/api/devices`
trả danh sách thiết bị. Đây là server cũ, chưa kết nối MySQL và còn lưu dữ liệu
trong RAM; số đo hiện đang rỗng và dữ liệu có thể mất khi service khởi động lại.
Thay đổi MySQL trong mã nguồn cục bộ chưa được deploy; không nhầm service công
khai với server local.

Blueprint và cấu hình service nằm trong repository công khai
`SparkQ1911/Smart-Home-App`; service hiện dùng cấu hình Free ở Singapore.
Không nâng cấp instance hoặc tạo dịch vụ trả phí nếu muốn tiếp tục dùng miễn
phí.

Render Free không yêu cầu chọn gói trả phí nhưng có hạn mức, có thể ngủ sau
15 phút không có yêu cầu, khởi động lại và làm mất trạng thái trong RAM.
Workspace có 750 giờ Free instance/tháng; khi hết hạn mức, service có thể bị
tạm ngưng. Không thêm phương thức thanh toán nếu mục tiêu là không phát sinh
phí; vượt hạn mức dịch vụ có thể ngừng hoạt động thay vì tiếp tục miễn phí.
Kiểm tra trang Usage/Billing của Render.

### Cấu hình MySQL khi deploy server

Backend dùng trực tiếp database `nha_thong_minh` và các bảng trong
[`tao_csdl.sql`](./tao_csdl.sql). Chạy file SQL một lần trên MySQL trước khi
khởi động server. Backend bổ sung các cột tương thích API nếu database cũ
chưa có, tạo tài khoản hệ thống và seed bốn thiết bị mẫu. Cấu hình
`MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, `MYSQL_USER` và
`MYSQL_PASSWORD` trong môi trường server; không commit hoặc gửi thông tin
đăng nhập database. `render.yaml` khai báo các giá trị cần nhập dưới dạng
secret. Render không cung cấp MySQL trong cấu hình này, nên phải có MySQL
host bên ngoài cho phép server kết nối; chưa cấu hình host thì server không
khởi động.

Tạo secret ngẫu nhiên dài tối thiểu 32 ký tự cho `SMART_HOME_AUTH_SECRET` và
`SMART_HOME_DEVICE_KEY`, cài đặt chúng ở server. Device key chỉ dùng cho
firmware REST; ESP32 MQTT dùng credentials của broker trong
`machine_config.py`. Không commit key, credentials MQTT hoặc Wi-Fi vào Git.
Kiểm tra `/api/health`; API cần trả về `"storage":"mysql"`.

Tài khoản, trạng thái thiết bị, lịch sử đổi trạng thái và từng lần đo DHT22
được lưu vào các bảng SQL. Lệnh đang chờ ESP32 vẫn ở RAM và hết hạn sau 30
giây, vì schema hiện tại chưa có bảng lệnh; app và ESP32 cần chạy cùng server
để điều khiển end-to-end.

Server MQTT bridge chỉ kết nối khi đã cấu hình `MQTT_USERNAME` và
`MQTT_PASSWORD` ở Render. Firmware MicroPython dùng cùng AIO Key qua TLS.
Các tài khoản trong thiết kế hiện tại vẫn dùng chung thiết bị,
số đo và lịch sử, chưa phân vùng nhà theo user; demo chưa có giới hạn tốc độ
đăng ký/đăng nhập.

Trên điện thoại cùng Wi-Fi với server, build app với IP nội bộ của máy chủ
(xem `ipconfig`, ví dụ `http://192.168.1.10:8080`). Nếu điện thoại đang nối
USB với ADB, có thể chạy app tự kết nối bằng:

```powershell
adb reverse tcp:8080 tcp:8080
flutter run -d <device-id> --dart-define=SMART_HOME_SERVER_URL=http://127.0.0.1:8080
```

App tự lấy dữ liệu mới mỗi 3 giây sau khi kết nối thành công. Server local lưu
số đo, trạng thái thiết bị, tài khoản và lịch sử vào MySQL; lệnh đang chờ vẫn
ở RAM. Chỉ nối ESP32 sau khi bản server mới đã deploy thành công, xác nhận
`/api/health` trả `"storage":"mysql"` và MQTT bridge kết nối Adafruit IO.
Android debug cho phép HTTP nội bộ để thử; bản release nên dùng HTTPS.

Firmware MicroPython vật lý gửi DHT22 qua feed
`<username>/f/sensor-temperature` và
`<username>/f/sensor-humidity`; trạng thái thiết bị đi qua các feed
`<username>/f/*-state`. REST endpoint
`POST /api/simulator/publish` với header `X-Device-Key` vẫn có sẵn cho client
REST khác; app đọc dữ liệu qua `GET /api/sensors/latest`. Bearer token.

Không dùng `localhost` trên điện thoại để trỏ tới máy tính chạy Server; hãy
dùng IP nội bộ của máy chủ. Trong `android/app/src/main/AndroidManifest.xml`,
đảm bảo có quyền Internet:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Với HTTP không mã hóa trên Android, cấu hình network security của bản Android
theo chính sách triển khai (chỉ bật cleartext khi cần cho môi trường phát
triển); ưu tiên HTTPS trong môi trường thực tế. Không nhúng mật khẩu, khóa
API hay thông tin Wi-Fi vào ứng dụng. Khi chạy trên Web, Server phải cho phép
CORS từ origin của ứng dụng; nên dùng HTTPS trong môi trường thực tế.

## Endpoint và JSON mặc định

Đường dẫn tập trung trong `lib/services/api_service.dart`, lớp `ApiEndpoints`; sửa nội bộ tại đó nếu
Server dùng API khác. Endpoint không được hiển thị trong màn hình Cài đặt.

| Phương thức | Endpoint | Dữ liệu mong đợi |
|---|---|---|
| POST | `/api/simulator/publish` | Client REST gửi sensor JSON + `X-Device-Key`; không dùng bởi firmware MQTT |
| GET | `/api/sensors/latest` | `{ "rooms": [...], "updatedAt": "..." }`; app lấy số đo mới nhất |
| GET | `/api/devices` | `{ "devices": [{ "id": "...", "name": "...", "type": "light", "status": "OFF", "room": "..." }] }` |
| GET | `/api/devices/{id}/status` | `{ "status": "ON" }` hoặc `{ "status": "OFF" }` |
| POST | `/api/devices/{id}/control` | App gửi desired state; trả HTTP 202 + `commandId` |
| GET | `/api/devices/{id}/commands/{commandId}` | App kiểm tra pending/completed/failed |
| GET | `/api/iot/devices/{id}/commands/pending` | Endpoint tương thích cho firmware REST cũ; firmware MQTT hiện tại không dùng |
| POST | `/api/iot/devices/{id}/state` | Firmware REST cũ báo trạng thái |
| GET | `/api/history` | `{ "history": [...] }` |
| POST | `/api/auth/register` | Đăng ký; trả token và hồ sơ (bản code cục bộ) |
| POST | `/api/auth/login` | Đăng nhập; trả token và hồ sơ (bản code cục bộ) |
| GET | `/api/auth/me` | Hồ sơ hiện tại; cần Bearer token (bản code cục bộ) |
| DELETE | `/api/auth/me` | Xóa tài khoản, cần token và xác nhận mật khẩu (bản code cục bộ) |

Trong code cục bộ, API app yêu cầu Bearer token; API ESP32 yêu cầu
`X-Device-Key` chỉ dùng cho firmware REST cũ; firmware MQTT xác thực với
Adafruit IO bằng username và AIO Key. MQTT bridge tắt nếu chưa cấu hình key.

Thiết bị theo ví dụ:

```json
{
  "id": "device_01",
  "name": "Đèn phòng khách",
  "type": "light",
  "status": "OFF"
}
```

Lệnh điều khiển được lưu trạng thái `pending`. MQTT bridge gửi lệnh lên topic
thiết bị tương ứng; ESP32 publish trạng thái thực tế và bridge cập nhật lệnh.
App polling trạng thái command; chỉ cập nhật giao diện khi
nhận `completed` với reported state. Nếu ESP32 không phản hồi trong 20 giây,
App báo timeout và không giả vờ rằng thiết bị đã đổi trạng thái. Mỗi thiết bị
chỉ có một lệnh đang chờ; lệnh chờ cũ hơn 30 giây hết hạn.

## Kiến trúc hệ thống và luồng dữ liệu

```text
Tầng IoT                         Tầng trung gian / Server                 Tầng App
┌─────────────────────┐         ┌──────────────────────────┐            ┌───────────────────┐
│ DHT22 / cảm biến    │         │ Python REST API trên      │  HTTPS     │ Flutter Android   │
│ ESP32 đọc mỗi chu kỳ├─ MQTT ─>│ Render + MQTT bridge     │<─ REST ───┤ xem sensor/device  │
│ Wi-Fi / board thật  │         │ xác thực, kiểm tra, lưu DB│            │ gửi lệnh bật/tắt  │
└─────────────────────┘         └─────────────┬────────────┘            └───────────────────┘
                                              │
                                              ▼
                                    ┌─────────────────────┐
                                    │ MySQL               │
                                    │ nguoi_dung          │
                                    │ thiet_bi + lịch sử  │
                                    │ + dữ liệu cảm biến  │
                                    └─────────────────────┘
```

### 1. Thiết bị IoT đẩy dữ liệu lên

1. ESP32 vật lý đọc DHT22 ở GPIO 15 mỗi 10 giây; LED đỏ, xanh lá, vàng,
   xanh dương lần lượt ở GPIO 17, 18, 22, 23.
2. ESP32 kết nối Wi-Fi và Adafruit IO MQTT bằng username/AIO Key qua TLS.
3. Firmware gửi nhiệt độ/độ ẩm lên hai feed Adafruit IO riêng.
4. MQTT bridge kiểm tra payload, ghi số đo vào MySQL để app đọc.

Payload hiện dùng:

```json
{
  "rooms": [
    {"room": "Phòng khách", "temperature": 28.5, "humidity": 60.0},
    {"room": "Nhà bếp", "temperature": 29.0, "humidity": 57.5}
  ]
}
```

Firmware cho thiết bị thật nằm ở `code_ESP32_va_trang_thu\main.py`. Firmware
đăng ký bốn topic điều khiển, áp dụng lệnh lên GPIO, rồi publish trạng thái
thực tế để server xác nhận.

### 2. App lấy dữ liệu từ server bằng cách nào?

App không đọc trực tiếp MySQL; chỉ server được kết nối database.
`ApiService` gửi HTTP GET/POST tới REST API,
nhận JSON, chuyển thành model Dart; `SmartHomeProvider` đưa dữ liệu lên màn
hình. Khi đăng nhập thành công, app gửi `Authorization: Bearer <token>` cho
các endpoint cần xác thực.

- Màn hình cảm biến gọi `GET /api/sensors/latest`. App đang polling khoảng
  mỗi 3 giây; người dùng cũng có thể kéo xuống để làm mới.
- Màn hình thiết bị gọi `GET /api/devices` để lấy tên, phòng, loại và trạng
  thái ON/OFF.
- Lịch sử gọi `GET /api/history`; lịch sử đổi trạng thái được lưu trong SQL.
- Khi bật/tắt, app gửi `POST /api/devices/{id}/control` với
  `{"state":"ON"}` hoặc `{"state":"OFF"}`. App chỉ đổi UI theo trạng thái
  server trả về, không tự coi lệnh gửi đi là thành công.
- `updatedAt` trong response sensor giúp app hiển thị thời điểm số đo được
  cập nhật; `rooms[]` là các phòng và giá trị riêng của mỗi phòng.

### 3. Cơ chế lệnh cho thiết bị thật

Khi app gửi lệnh, REST API publish lệnh lên Adafruit IO feed tương ứng. ESP32
áp dụng lệnh và báo trạng thái lên feed state riêng; bridge cập nhật trạng
thái thiết bị và app nhận kết quả qua REST API. Chỉ xác nhận hoạt động
end-to-end sau khi đã cấu hình broker, nạp firmware lên ESP32 thật, thấy số đo
cập nhật và kiểm tra phản hồi của từng GPIO/tải.

Luồng điều khiển app–ESP32 dùng MQTT; app chỉ giao tiếp với REST API:

```text
App --POST desired state--> REST API --MQTT TLS--> ESP32 thật
ESP32 --MQTT sensor + actual state--> bridge --> MySQL
App --GET device/sensor state--> REST API --> hiển thị trạng thái
```

Server chỉ cập nhật trạng thái ON/OFF bền vững sau khi nhận trạng thái thực
tế từ ESP32. Lệnh có `commandId`, `deviceId`, `desiredState`, `createdAt`,
`status`; phản hồi có `commandId`, `reportedState`, `reportedAt`. Lệnh chỉ
nằm trong RAM cho tới khi hoàn tất hoặc server khởi động lại. Adafruit IO free
giới hạn 30 data points/phút; firmware gửi mỗi số đo cách nhau hơn một giây,
giảm số đo mỗi cặp xuống mỗi 10 giây và bridge giãn cách publish lệnh.

### 4. Thiết kế cơ sở dữ liệu

Backend dùng trực tiếp các bảng trong `tao_csdl.sql`:

| Bảng | Dữ liệu được lưu |
|---|---|
| `nguoi_dung` | Email đăng nhập, tên hiển thị và password hash PBKDF2; không lưu mật khẩu rõ |
| `thiet_bi` | Thiết bị app/ESP32, trạng thái, phòng và mã định danh API |
| `lich_su_trang_thai` | Trạng thái/action và thời điểm đổi trạng thái |
| `du_lieu_cam_bien` | Mỗi lần đo nhiệt độ/độ ẩm DHT22 |

Server tự thêm các cột cần cho API vào database đã tạo từ script. Các lần đo
được lưu liên tục; `GET /api/sensors/latest` chỉ trả số đo mới nhất mỗi phòng.
Các lệnh đang chờ vẫn ở RAM và mất khi server dừng; tài khoản, trạng thái thiết
bị, lịch sử và số đo đã ghi được khôi phục từ MySQL.

### Phân công phần việc cho nhóm

- **IoT:** nối cảm biến/LED với ESP32, đọc số đo, kết nối Wi-Fi/MQTT TLS,
  nhận feed lệnh và publish feed trạng thái thực tế.
- **Server trung gian:** định nghĩa REST/MQTT contract, xác thực, kiểm tra
  payload, lưu MySQL, cung cấp sensor/device/history API, chuyển lệnh và
  ghi log/lỗi.
- **App:** đăng nhập, gọi REST API qua HTTPS, parse JSON, hiển thị sensor và
  ON/OFF, gửi lệnh, hiển thị loading/lỗi/trạng thái được server xác nhận.
- **Kiểm thử tích hợp:** dùng chung ví dụ JSON và device/sensor IDs; xác minh
  một lần đo đi từ ESP32 đến app và một lệnh đi ngược về thiết bị.

Deliverable tuần 1–2 nên gồm sơ đồ kiến trúc, luồng dữ liệu hai chiều,
API contract/JSON mẫu, sơ đồ collection và demo kiểm thử. Cần trình bày riêng
phần đã chạy được và phần dự kiến (đặc biệt MySQL production và lệnh relay
thật).
