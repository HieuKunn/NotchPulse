Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### Có gì mới trong bản v2.9.3.1:
- 🔓 **Tự động mở khoá máy Face ID chuẩn xác**: Sửa dứt điểm lỗi chỉ điền mật khẩu mà chưa tự hoàn tất mở khoá. Tối ưu thời gian trễ và giả lập chu kỳ phím Return (`0x24`) ở tầng phần cứng HID để `SecurityAgent` nhận diện và mở khoá máy tính ngay lập tức.
- 🎨 **Khắc phục triệt để lỗi viền màn hình khoá (Lock Screen Media & Face ID)**:
  - Loại bỏ hoàn toàn phần bóng mờ góc vuông bị lộ ngoài viền bo cong của cửa sổ Face ID và Media màn hình khoá.
  - Media màn hình khoá tự động chiếm chuẩn 90% diện tích của chính màn hình đang chọn hiển thị Notch (hỗ trợ hoàn hảo cả màn hình phụ ngoại vi), bố cục immersive cân đối.
- 🔄 **Software Updates trong Settings**:
  - Bổ sung nút bấm trực tiếp "Check for Updates…" ngay trong **Settings ➔ About ➔ Software updates** bên cạnh Menu Bar icon.
- ⚡ **Kế thừa các cải tiến v2.9.3**:
  - Tích hợp framework cập nhật Sparkle 2.
  - Nâng cấp trải nghiệm Calendar (cuộn mượt mà tự do, vùng click full-cell).
  - Tai thỏ Face ID thông minh liền mạch mép trên màn hình Mac và co gọn tinh tế trên màn hình ngoài.
  - Hiển thị Swap Memory trong System Monitor.
