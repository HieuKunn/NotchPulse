Official NotchPulse macOS installer (.dmg) and application bundle (.app.zip) automatically packaged from commit {{COMMIT_SHA}}.

### Có gì mới trong bản v2.9.3:
- 🚀 **Tự động cập nhật (Sparkle Auto-Update)**: Tích hợp hệ thống tự động kiểm tra và nâng cấp trực tiếp qua GitHub Releases, cài đè phiên bản mới nhanh chóng mà không cần tải DMG thủ công.
- 📅 **Nâng cấp trải nghiệm Calendar**:
  - Vùng bấm nhận click toàn diện trên từng ô ngày (kể cả khoảng trống giữa thứ và số ngày), khắc phục triệt để lỗi trượt click.
  - Hỗ trợ cuộn tự do lướt qua nhiều ngày bằng con lăn chuột (mouse wheel) và trackpad mượt mà, không còn bị khựng giật cục từng ngày.
  - Mở rộng dải ngày khả dụng (30 ngày quá khứ, 60 ngày tương lai).
- 🔒 **Tối ưu hiển thị màn hình khoá (Lock Screen Media & Face ID)**:
  - Ẩn nhãn karaoke thừa, tự động căn giữa hài hoà khi bài hát không có lyrics và chia đôi cân đối khi có lyrics.
  - Xử lý triệt để viền vuông góc bị lộ, bo góc mượt mà đồng bộ với giao diện macOS.
  - Tai thỏ Face ID liền khối thông minh: Tự động nối dài chiều cao liền mạch từ mép trên màn hình Mac có tai thỏ; tự động co gọn chiều cao (44px) tinh tế khi hiển thị trên màn hình phụ ngoại vi.
  - Sửa lỗi reset trạng thái ổ khoá Face ID khi khoá màn hình máy.
- 💾 **Hiển thị Swap Memory (Bộ nhớ tráo đổi)**: Thêm thông số dung lượng Swap đã dùng trong RAM card của System Monitor và Settings Live Preview, đọc trực tiếp từ kernel macOS Darwin `sysctl`.
- 🎛️ **Live Notch Width Preview**: Xem trước trực tiếp kích thước notch khi kéo thanh trượt điều chỉnh độ rộng trong Settings.
- ⚡ Tối ưu hiệu năng, khắc phục timeout type-check trên Xcode 16.2 / Swift 6 và sửa các lỗi nhỏ.
