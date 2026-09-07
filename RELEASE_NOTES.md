Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### 🚀 Có gì mới trong bản v2.9.4.5:
- 🔒 **Khắc phục triệt để bảo mật Face ID (Sinh trắc học chính xác tuyệt đối)**:
  - Sửa lỗi hệ toạ độ giữa Apple Vision và CoreGraphics: Cắt chính xác 100% từng đường nét khuôn mặt (trán, mắt, mũi, miệng, cằm) thay vì cắt nhầm xuống áo/ngực.
  - Siết chặt ngưỡng nhận diện sinh trắc học (`matchThreshold = 0.32`), ngăn chặn hoàn toàn việc người khác mở khoá.
  - Tích hợp cơ chế xác thực 2 khung hình liên tiếp chống nhận diện giả do chớp sáng/ánh sáng ngẫu nhiên.
  - *Lưu ý: Bạn hãy vào Cài đặt Face ID xoá khuôn mặt cũ và bấm "Đăng ký khuôn mặt mới" để lưu vector chuẩn.*
- 🖤 **Face ID Màn hình khoá Chuẩn Inline Độc quyền**:
  - Loại bỏ hoàn toàn kiểu pop-down thả xuống che màn hình; chuyển sang hiển thị Inline thanh lịch.
  - Màn hình MacBook: Thiết kế cánh đôi (dual-wing) tách biệt - icon nụ cười Face ID nằm ở cánh bên trái hoàn toàn ngoài camera vật lý của Mac, cánh phải hiển thị trạng thái ổ khóa.
  - Màn hình phụ / rời: Hiển thị viên thuốc 34px bo tròn thanh thoát ôm sát mép trên.
- 🔄 **Cập nhật trong ứng dụng (Sparkle Auto-Update)**:
  - Tích hợp chuẩn xác chữ ký Ed25519 cho Sparkle Updater, sửa lỗi 404 Appcast và cho phép tải trực tiếp các bản cập nhật mới từ trong ứng dụng.
- ⚡ **Siêu tối ưu hiệu năng & Triệt tiêu hoàn toàn giật lag CPU**:
  - Chuyển đổi toàn bộ sang `LazyHStack`, duy trì mức CPU dưới **0.5%** và RAM cực nhẹ.
- 🎵 **Trải nghiệm Media & Lời bài hát Karaoke Màn hình khoá**:
  - Chuyển động êm ái theo màu Album, nâng vị trí thanh media tránh đè avatar tài khoản.
  - Dòng lời đang phát in đậm sáng bóng, cỡ chữ lớn chuẩn UX.
- 📅 **Lịch & Sự kiện Tối giản, Tự Động Định Vị Theo Giờ Thực**:
  - Tự động cuộn đến sự kiện đang diễn ra trong khung giờ hiện tại hoặc sự kiện kế tiếp trong ngày mà không tốn tài nguyên.
