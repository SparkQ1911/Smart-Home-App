# Smart Home App

Ứng dụng Flutter bằng tiếng Việt để giám sát cảm biến và điều khiển thiết bị
IoT thông qua REST API. Khi khởi động, app tự kết nối API demo công khai
`https://smart-home-demo-api.onrender.com`; có thể đổi Server trong **Cài đặt**
hoặc chọn **Chuyển về chế độ demo** để dùng dữ liệu minh họa.

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

## Kết nối Server

App tự kết nối server công khai khi mở. Để dùng server khác:

1. Mở tab **Cài đặt**.
2. Nhập URL gốc, ví dụ `http://192.168.1.10:8080`.
3. Chọn **Kiểm tra và kết nối**. Ứng dụng gọi `GET /api/devices`; chỉ khi
   thành công trạng thái kết nối mới được xác nhận. Lỗi được hiển thị ngay
   trên màn hình.
4. Dùng **Chuyển về chế độ demo** để trở lại dữ liệu minh họa.

### Thử bằng Wokwi và REST server

Server mẫu chạy bằng Python 3, không cần cài thư viện ngoài:

```powershell
python server\smart_home_server.py
```

Mở [dự án Wokwi Smart Home đã tạo](https://wokwi.com/projects/479187038352651265)
hoặc tạo dự án ESP32 mới, rồi chép
`wokwi\diagram.json`, `wokwi\sketch.ino` và `wokwi\libraries.txt` vào dự án.
Mạch gồm ESP32 và bốn cảm biến DHT22; bấm Start Simulation để gửi số đo lên
`POST /api/simulator/publish` mỗi 5 giây. Có thể bấm vào từng DHT22 trong
Wokwi để thay đổi nhiệt độ/độ ẩm. Giá trị được cập nhật theo phòng ở
`GET /api/sensors/latest`.

Wokwi Public Gateway gửi được tới HTTPS công khai, nhưng không truy cập được
server chạy trên máy tính/mạng LAN. Để thử với server local, cần Wokwi Private
IoT Gateway (chỉ khả dụng theo gói Wokwi trả phí): tải và chạy gateway từ
[wokwi/wokwigw](https://github.com/wokwi/wokwigw/releases/latest), sau đó
trong editor Wokwi chọn **F1 → Enable Private Wokwi IoT Gateway**. Firmware
dùng `host.wokwi.internal:8080` nếu thử server local (hãy đổi `kServerUrl`
trong sketch). Với server HTTPS công khai, Wokwi Public Gateway dùng được
mà không cần Private Gateway; dữ liệu gửi qua Public Gateway có thể bị giám
sát. Firmware mẫu không xác minh chứng chỉ TLS và chỉ được dùng với dữ liệu
giả lập không nhạy cảm; không gửi thông tin đăng nhập, bí mật hoặc dữ liệu
thiết bị thật.

### Deploy server demo công khai trên Render Free

Server demo đã được deploy ở gói Free trên Render:
`https://smart-home-demo-api.onrender.com`. Có thể kiểm tra trạng thái tại
`https://smart-home-demo-api.onrender.com/api/health`.

App tự kết nối URL này khi khởi động; không cần nhập lại trong **Cài đặt**.
Để gửi dữ liệu mô phỏng, mở [dự án Wokwi đã tạo](https://wokwi.com/projects/479187038352651265)
và bấm **Start the simulation**. Firmware gửi số đo đến server công khai
mỗi 5 giây; app đọc dữ liệu mới mỗi 3 giây.

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

API demo công khai chưa có đăng nhập: người khác có thể đọc dữ liệu và gửi
số đo giả lập. Chỉ dùng dữ liệu Wokwi, tuyệt đối không nối thiết bị thật,
gửi dữ liệu riêng tư hay khóa bí mật. Dữ liệu trong RAM mất khi service ngủ,
khởi động lại hoặc deploy lại.

Wokwi Public Gateway truy cập Internet nhưng không truy cập được server local.
Chỉ gửi số đo giả lập; không gửi bí mật hoặc thông tin xác thực qua gateway.

Trên điện thoại cùng Wi-Fi với server, nhập IP nội bộ của máy chủ trong
**Cài đặt** (xem `ipconfig`, ví dụ `http://192.168.1.10:8080`). Nếu điện thoại
đang nối USB với ADB, có thể chạy app tự kết nối bằng:

```powershell
adb reverse tcp:8080 tcp:8080
flutter run -d <device-id> --dart-define=SMART_HOME_SERVER_URL=http://127.0.0.1:8080
```

App tự lấy dữ liệu mới mỗi 3 giây. Server giữ số đo trong bộ nhớ; khi dừng
server, dữ liệu đo sẽ bị xóa. Thiết
bị mẫu có thể điều khiển qua app và server trả lại trạng thái đã xác nhận.
Server mẫu không có xác thực và chỉ phù hợp thử nghiệm trong mạng nội bộ;
không mở trực tiếp ra Internet. Android debug cho phép HTTP nội bộ để thử,
còn bản release nên dùng HTTPS.

Endpoint nhận mẫu: `POST /api/simulator/publish` với JSON gồm `updatedAt` và
mảng `rooms`; app đọc dữ liệu qua `GET /api/sensors/latest`.

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

Đường dẫn tập trung trong `lib/services/api_service.dart`, lớp
`ApiEndpoints`; sửa giá trị mặc định tại đó nếu Server dùng API khác.

| Phương thức | Endpoint | Dữ liệu mong đợi |
|---|---|---|
| GET | `/api/devices` | Mảng thiết bị hoặc object `{ "devices": [...] }` |
| GET | `/api/sensors/latest` | Object có `temperature`, `humidity`, `updatedAt` |
| GET | `/api/devices/{id}/status` | `{ "status": "ON" }` hoặc `{ "state": "OFF" }` |
| POST | `/api/devices/{id}/control` | Gửi `{ "state": "ON" }` hoặc `{ "state": "OFF" }` |
| GET | `/api/history` | Mảng sự kiện hoặc object `{ "history": [...] }` |

Thiết bị theo ví dụ:

```json
{
  "id": "device_01",
  "name": "Đèn phòng khách",
  "type": "light",
  "status": "OFF"
}
```

Lệnh điều khiển dùng JSON. Sau POST, ứng dụng chỉ đổi trạng thái trên giao
diện khi Server trả trạng thái mới; nếu phản hồi POST không có trạng thái,
ứng dụng gọi endpoint trạng thái để lấy xác nhận. Mỗi thiết bị chỉ có một
lệnh điều khiển đang chạy tại một thời điểm. API lịch sử trả HTTP 404/501
được nhận diện là chưa hỗ trợ; ứng dụng không giả lập lịch sử Server.

## Kiến trúc

- `lib/models/`: model thiết bị, cảm biến và lịch sử.
- `lib/services/api_service.dart`: cấu hình URL/endpoint, HTTP timeout, giải
  mã JSON và xử lý lỗi HTTP/mạng.
- `lib/providers/smart_home_provider.dart`: trạng thái demo/server, tải dữ
  liệu và chờ xác nhận lệnh thiết bị.
- `lib/screens/`: Trang chủ, Thiết bị, Cảm biến, Lịch sử, Cài đặt.
- `lib/widgets/`: thẻ thiết bị, cảm biến và trạng thái kết nối.

Luồng hệ thống: ESP32 gửi số đo/trạng thái đến Server (HTTP hoặc MQTT);
Server lưu trữ và cung cấp REST API; ứng dụng đọc API và gửi yêu cầu điều
khiển; Server chuyển lệnh đến ESP32 rồi xác nhận trạng thái. Giao thức,
định dạng JSON, xác thực và bảo mật API cần được thống nhất với nhóm Server
trước khi triển khai thực tế.
