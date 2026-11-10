# Artisan Mobile

Ứng dụng Flutter (Android + iOS) để **ghi và điều khiển mẻ rang cà phê qua Modbus TCP (WiFi)**.
Giao diện mô phỏng theo Artisan. File lưu ra là `.alog`, **mở được bằng Artisan trên máy tính và ngược lại**.

## Tính năng

| # | Tính năng | Ghi chú |
|---|-----------|---------|
| 1 | Đọc **BT**, **ET**, **CT** mỗi 1–3 giây | Modbus TCP, FC3/FC4, kiểu INT16/UINT16/INT32/FLOAT32, hệ số chia, hiệu chỉnh |
| 2 | Đồ thị nhiệt độ + **ΔBT (RoR, °C/phút)** + đồng hồ dự đoán **»DRY / »FCs** | RoR tính bằng hồi quy tuyến tính trên 20 giây (giống mặc định của Artisan), có làm mượt |
| 3 | **Tự nhận** CHARGE, TP, DRY END, FC START, DROP | Theo đúng thuật toán Artisan (Auto CHARGE/DROP, TP). DRY END = 150°C, FC START = 198°C (sửa trong Cài đặt). Sửa tay: Menu → Sự kiện |
| 4 | Lưu mẻ rang, **lịch sử**, mở xem lại | Lưu `.alog` trong bộ nhớ app; tìm kiếm; nhập / xuất file |
| 5 | **Profile Auto** hiện làm đường nền để rang theo | Căn theo CHARGE |
| 6 | **Điều khiển gas, quạt, trống** + **nút tuỳ chỉnh** | Thanh trượt và nút dùng **lệnh Modbus Command giống Artisan**: `write([3,0,{}])`, `writem(3,1,{})`, `wcoil`… Nút loại ±Air/±Burner cộng/trừ giá trị |
| 7 | **Rang tự động (AUTO)** | Chọn mẻ mẫu bằng nút **Profile Auto**. Lúc CHARGE đặt Gas/Trống/Quạt như mẻ mẫu; sau đó chỉnh lại tại đúng các mốc BT mà mẻ mẫu đã chỉnh (giống Artisan *Playback Events – theo BT*) |

## 1. Cài môi trường (làm 1 lần, trên Windows)

1. Cài **Flutter SDK 3.44 trở lên** (khuyên dùng bản stable mới nhất): https://docs.flutter.dev/get-started/install/windows/mobile
2. Cài **Android Studio** (có Android SDK). Mở Android Studio một lần để nó tải SDK.
3. Mở **Command Prompt** rồi chạy `flutter doctor`. Làm theo hướng dẫn cho tới khi mục *Flutter* và *Android toolchain* có dấu ✓ (thường cần chạy `flutter doctor --android-licenses`).
4. Trên điện thoại Android: bật **Tuỳ chọn nhà phát triển → Gỡ lỗi USB**, rồi cắm cáp vào máy tính.

## 2. Thiết lập dự án (lần đầu)

Nhấp đúp **`setup.bat`** trong thư mục này. Script sẽ:

- tạo thư mục `android/` và `ios/` bằng `flutter create`. Code trong `lib/` được giữ nguyên.
- thêm quyền mạng (INTERNET) cho Android và quyền *Local Network* cho iOS.
- tải thư viện (`flutter pub get`).

Trên macOS/Linux thì chạy `./setup.sh`.

## 3. Chạy và cài lên điện thoại

```bash
flutter run                      # chạy thử trên điện thoại đang cắm cáp
flutter build apk --release      # tạo file cài đặt
```

File APK nằm ở `build\app\outputs\flutter-apk\app-release.apk`. Bạn có thể gửi file này qua Zalo hoặc Drive để cài lên các máy khác. Máy nhận cần cho phép *cài ứng dụng không rõ nguồn gốc*.

Muốn chạy kiểm thử thì dùng `flutter test`.

## 4. Sử dụng

Kết nối điện thoại vào WiFi của bộ chuyển đổi Modbus, rồi bấm **ON**.

1. **ON** kết nối và bắt đầu ghi. **OFF** dừng ghi và hỏi có lưu không. **RESET** xoá màn hình.
2. Khi đổ hạt vào lồng, bấm **CHARGE**. Đồng hồ tính từ 00:00 kể từ lúc này. Tiếp theo bấm TP, DRY END, FC START, DROP theo thứ tự.
3. Thanh trượt bên trái (nằm dưới đáy nếu cầm dọc) dùng để điều khiển Gas, Quạt, Trống. Mỗi lần thả tay, app gửi lệnh Modbus và ghi lại một sự kiện. Sự kiện hiện trên đồ thị dạng bậc thang, ví dụ `B60`.
4. Mở **Menu ☰** để vào:
   - **Thuộc tính mẻ rang**: tên mẻ, loại hạt, khối lượng vào/ra, ghi chú
   - **Lịch sử rang**: mở xem, xuất `.alog`, nhập `.alog` từ Artisan, xoá
   - **Cài đặt**: kết nối, kênh đọc, điều khiển, trục đồ thị
5. Xoay ngang điện thoại để có bố cục giống Artisan nhất: điều khiển bên trái, đồ thị ở giữa, LCD bên phải.

## 5. Cấu hình Modbus TCP

Vào **Cài đặt**, nhập IP và cổng (thường là 502) của PLC hoặc bộ chuyển đổi Modbus TCP. Bấm **Kiểm tra kết nối & đọc thử nhiệt độ** để thử.

Bảng thanh ghi mặc định (sửa được trong Cài đặt):

| Kênh | Slave | Thanh ghi | Mã hàm | Kiểu | Chia cho |
|------|-------|-----------|--------|------|----------|
| BT – nhiệt độ hạt | 1 | 0 | 3 | INT16 | 10 |
| ET – nhiệt độ môi trường | 1 | 1 | 3 | INT16 | 10 |
| CT – nhiệt độ buồng đốt | 1 | 2 | 3 | INT16 | 10 |
| Gas (Burner) – ghi | 1 | 10 | 6 | 0–100 | |
| Quạt (Air) – ghi | 1 | 11 | 6 | 0–100 | |
| Trống (Drum) – ghi | 1 | 12 | 6 | 0–100 | |
| Van gió (Damper) – ghi (ẩn) | 1 | 13 | 6 | 0–100 | |

- Địa chỉ thanh ghi tính **từ 0**. Ví dụ thanh ghi 40001 nhập là 0, thanh ghi 40011 nhập là 10.
- "Chia cho 10": PLC gửi 2005 thì app hiểu là 200.5 °C.
- Giá trị ghi xuống PLC = giá trị thanh trượt × *Hệ số nhân* + *Cộng thêm*. Ví dụ biến tần cần 0–5000 thì đặt hệ số nhân = 50.
- Điện thoại và PLC phải **cùng mạng WiFi/LAN**.

## 6. Tương thích Artisan

- Ứng dụng đọc và ghi `.alog` theo đúng định dạng của Artisan. Artisan dùng `repr(dict)` của Python để ghi và `ast.literal_eval` để đọc. Các khoá và kiểu dữ liệu khớp với `ProfileData` của Artisan.
- Cách quy đổi dữ liệu:
  - ET được lưu vào `temp1`, BT vào `temp2`.
  - CHARGE, DRY END, FC START, DROP được lưu vào `timeindex`.
  - TP được lưu vào `computed.TP_idx`. Khi mở file, Artisan tự tính lại TP.
- **CT** được lưu thành *thiết bị phụ* `+MODBUS 34`, kênh 1, tên `CT`. Artisan sẽ hiện CT như một đường phụ.
- Sự kiện điều khiển được lưu vào `specialevents`, theo loại Air/Drum/Damper/Burner và cách mã hoá giá trị của Artisan.
- Khi mở một file từ Artisan rồi lưu lại, mọi thông tin khác trong file được giữ nguyên.
- File Artisan dùng °F sẽ được đổi sang °C khi mở.
- **Lưu ý:** Khi mở trên máy tính, Artisan (bản 4.2 trở lên) có thể hỏi *"Not a genuine Artisan profile. Load it anyway?"*. Câu hỏi này xuất hiện vì file không do Artisan tạo ra. Chọn **Yes** để mở.
- Để chuyển file qua lại: ở màn hình Lịch sử, dùng **Xuất file .alog** để gửi sang máy tính. Dùng **📂 Nhập** để lấy file `.alog` từ Artisan vào điện thoại.

## 7. iOS

Muốn build cho iPhone thì cần **máy Mac có Xcode**. Chạy `./setup.sh`, sau đó `flutter run` hoặc `flutter build ipa`. Lần đầu kết nối, iOS sẽ hỏi quyền *mạng cục bộ*, hãy chọn **Cho phép**.

## 8. Cấu trúc mã nguồn

```
lib/
  main.dart                     khởi động app
  alog/python_literal.dart      đọc/ghi cú pháp Python literal (.alog)
  models/roast_profile.dart     mô hình mẻ rang <-> .alog
  modbus/modbus_tcp.dart        client Modbus TCP (FC3/4/5/6/16)
  services/settings.dart        cài đặt (lưu JSON)
  services/roaster_device.dart  thiết bị Modbus TCP
  services/roast_storage.dart   thư viện file .alog
  logic/ror.dart                tính RoR
  logic/roast_controller.dart   lấy mẫu, sự kiện, điều khiển, nền, dự đoán, rang tự động
  logic/auto_events.dart        tự nhận CHARGE/TP/DRY/FCs/DROP (theo Artisan)
  logic/auto_replay.dart        rang tự động: phát lại thay đổi Gas/Trống/Quạt theo BT
  modbus/modbus_command.dart    lệnh Modbus Command kiểu Artisan
  ui/                           giao diện (đồ thị, LCD, nút, cài đặt, lịch sử)
assets/profiles/                profile mẫu (tự tạo bằng mô phỏng)
test/                           kiểm thử
```

---
Đây là ứng dụng viết mới. Nó chỉ tham khảo định dạng file và cách hiển thị của [Artisan](https://github.com/artisan-roaster-scope/artisan) (GPL v3), không sao chép mã nguồn của Artisan. Đây không phải sản phẩm chính thức của dự án Artisan.
