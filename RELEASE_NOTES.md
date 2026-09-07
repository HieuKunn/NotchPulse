Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### 🚀 Có gì mới trong bản v2.9.4.3:
- 🛡️ **Sửa lỗi mở ứng dụng & Đóng gói Codesign đầy đủ Entitlements**:
  - Tích hợp chuẩn xác toàn bộ tệp quyền (`NotchPulse.entitlements` và `NotchPulseXPCHelper.entitlements`) trong quá trình đóng gói release, đảm bảo app không bị Gatekeeper từ chối khởi chạy.
  - Hướng dẫn mở ứng dụng không bị chặn Gatekeeper/Quarantine: Chạy lệnh `xattr -cr /Applications/NotchPulse.app` hoặc nhấn chuột phải chọn Open.
- 👁️ **Tuỳ chọn Kiểu hiển thị Face ID (Pop-down / Inline) & Bo cong Notch Chân thực**:
  - Hỗ trợ 2 kiểu hiển thị Face ID tại màn hình khoá trong Cài đặt:
    - **Thả xuống (Pop-down)**: Notch mở rộng êm ái xuống dưới camera với biểu tượng 3D Face ID lớn nổi bật.
    - **Gọn trong Notch (Inline)**: Nằm ngang gọn gàng, tinh tế bên trong chiều cao của Notch mà không rủ xuống màn hình.
  - Các góc viền Notch được thiết kế lại: bo cong góc dưới mềm mại chuẩn Apple (24px) và hai tai trên mở rộng ôm sát mép viền (bezel) như notch thật.
- ⚡ **Siêu tối ưu hiệu năng & Triệt tiêu hoàn toàn giật lag CPU**:
  - Chuyển đổi thanh lịch sang `LazyHStack`, giảm tải CPU từ 80% xuống dưới **0.5%** và bộ nhớ RAM về mức cực nhẹ.
- 🎵 **Trải nghiệm Media Màn hình khoá Siêu mượt**:
  - Không chớp màn hình, hình nền chuyển động theo màu Album, nâng vị trí thanh media tránh đè avatar tài khoản.
- 🎤 **Karaoke & Lời bài hát Tinh tế**:
  - Dòng lời đang phát in đậm sáng bóng, tăng cỡ chữ chuẩn UX, không bị che lấp khi zoom.
- 📅 **Lịch & Sự kiện Tối giản, Tự Động Định Vị Theo Giờ Thực**:
  - Tự động cuộn đến sự kiện đang diễn ra trong khung giờ hiện tại hoặc sự kiện kế tiếp trong ngày mà không tốn pin/CPU/RAM.
  - Giao diện sự kiện được tinh giản tối đa theo phong cách native macOS nguyên bản, loại bỏ các huy hiệu rối mắt.

