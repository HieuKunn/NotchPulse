Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### Có gì mới trong bản v2.9.3.2:
- 🔒 **Khôi phục hoàn toàn hiển thị trên Màn hình khoá (Lock Screen Media & Face ID)**:
  - Khôi phục cơ chế uỷ quyền không gian SkyLight (`SkyLightOperator`) đảm bảo cả cửa sổ Face ID và Media trình phát nhạc luôn luôn xuất hiện chuẩn xác ngay khi người dùng khoá máy tính.
  - Xử lý triệt để tận gốc lỗi viền vuông mờ: Loại bỏ bóng đổ gaussian bị viền cửa sổ cắt ngang (`window boundary clipped shadow`) và loại bỏ `darkAqua` backdrop layer thừa, giúp bo góc cong hoàn hảo, 100% trong suốt mượt mà trên mọi hình nền.
  - Cửa sổ Media nhận diện đúng màn hình đang chọn hiển thị Notch (`getTargetScreen()`), chế độ phóng to chiếm chuẩn 90% diện tích của màn hình đó.
- 🔓 **Tự động mở khoá máy Face ID**: Tối ưu chu kỳ phím Return (`0x24`) qua HID event tap với khoảng nghỉ hợp lý để `SecurityAgent` nhận diện và mở khoá tức thì.
- 🔄 **Software Updates trong Settings**: Nút "Check for Updates…" ngay trong **Settings ➔ About ➔ Software updates**.
