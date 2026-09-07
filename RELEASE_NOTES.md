Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### 🚀 Có gì mới trong bản v2.9.4.2:
- 👁️ **Tuỳ chọn Kiểu hiển thị Face ID (Pop-down / Inline) & Bo cong Notch Chân thực**:
  - Hỗ trợ 2 kiểu hiển thị Face ID tại màn hình khoá:
    - **Thả xuống (Pop-down)**: Notch mở rộng êm ái xuống dưới camera với biểu tượng 3D Face ID lớn nổi bật.
    - **Gọn trong Notch (Inline)**: Nằm ngang gọn gàng, tinh tế bên trong chiều cao của Notch mà không rủ xuống màn hình.
  - Các góc viền Notch được thiết kế lại hoàn toàn: bo cong góc dưới mềm mại chuẩn Apple (24px) và hai tai trên mở rộng ôm sát mép viền (bezel) như notch thật.
- ⚡ **Siêu tối ưu hiệu năng & Triệt tiêu hoàn toàn giật lag CPU**:
  - Chuyển đổi thanh lịch sang `LazyHStack`, loại bỏ vòng lặp tính toán ngày vô tận trong bộ nhớ. Giảm tải CPU từ 80% xuống dưới **0.5%** và bộ nhớ RAM về mức cực nhẹ.
  - Tối ưu hóa điều hướng cuộn thanh lịch mượt mà, loại bỏ triệt để xung đột render giữa AppKit và SwiftUI.
- 🎵 **Trải nghiệm Media Màn hình khoá Siêu mượt**:
  - Loại bỏ hoàn toàn hiện tượng chớp/nhấp nháy màn hình khi tương tác với các nút điều khiển âm nhạc.
  - Hình nền chuyển màu linh hoạt và đồng bộ theo gam màu chủ đạo của Album khi phóng to toàn màn hình.
  - Nâng vị trí thu nhỏ của thanh Media lên cao hơn, giữ khoảng cách thoáng đãng và không bị chèn vào ảnh đại diện/tên tài khoản macOS.
- 🎤 **Karaoke & Lời bài hát Tinh tế**:
  - Dòng lời bài hát đang phát được thiết kế nổi bật với hiệu ứng sáng bóng, in đậm và tăng cỡ chữ chuẩn UX, khắc phục triệt để lỗi tràn/lấp khung nhìn khi zoom.
- 🛡️ **Tối ưu hoá Face ID & Mở khoá Thông minh**:
  - Tự động huỷ tác vụ Face ID ngay lập tức nếu máy đã được mở khoá bằng Touch ID hoặc nhập mật khẩu.
  - Đảm bảo biểu tượng trạng thái Face ID (chấm xanh lá) luôn hiển thị ưu tiên trên Notch ngay cả khi đang xem Media toàn màn hình.
