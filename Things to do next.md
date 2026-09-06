# Things to do next 🚀

## 📌 Kế hoạch phát triển phiên bản NotchPulse v2.0

- [x] **Tích hợp Face ID mở khoá Mac (Zero-Overhead)**:
  - Sử dụng Apple Vision Framework kết hợp chip Neural Engine (NPU) để nhận diện khuôn mặt siêu tốc (0.2s - 0.4s).
  - Tự động kích hoạt camera đúng 1s khi màn hình khoá sáng lên, không chạy ngầm liên tục, tiêu tốn 0% CPU/RAM khi không dùng.

- [x] **Trình phát nhạc Màn hình khoá phong cách iPhone (Lock Screen Media Player)**:
  - Hiển thị giao diện nghe nhạc đè lên màn hình khoá macOS bằng window layer `SkyLightWindow`.
  - Thiết kế 2 cột chuẩn iPhone / Dynamic Island:
    - **Một bên**: Ảnh bìa album lớn (Spotify, Apple Music, YouTube) + thông tin bài hát & hiệu ứng sóng âm.
    - **Một bên**: Lời bài hát cuộn chạy theo thời gian thực (Synced Lyrics Karaoke effect).
