# NotchPulse Project Guidelines & Memory Rules

File này chứa các quy tắc và lưu ý quan trọng cho dự án NotchPulse. Các AI Agent làm việc trên codebase này BẮT BUỘC phải đọc và tuân thủ tự động.

> **CRITICAL RULE FOR ALL AGENTS:** Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

---

## 1. Quy định Commit Message & Release Notes chuẩn tiếng Anh (BẮT BUỘC)
- **Commit Message Chi Tiết:** Mỗi khi commit code, BẮT BUỘC phải viết nội dung mô tả chi tiết từng thay đổi, sửa lỗi (itemized list). KHÔNG dùng các câu commit chung chung như "update code", "fix bug".
- **Release Notes Bằng Tiếng Anh Chi Tiết (`RELEASE_NOTES.md`):** Mỗi khi thực hiện Release phiên bản mới (ví dụ: `v3.1.2`), Agent BẮT BUỘC phải cập nhật file `RELEASE_NOTES.md` ở thư mục gốc repo với nội dung **HOÀN TOÀN BẰNG TIẾNG ANH**, mô tả đầy đủ các tính năng mới (`🚀 Features`), sửa lỗi (`🐛 Fixes`), tối ưu hiệu năng (`⚡ Performance`), và hướng dẫn cập nhật. KHÔNG ĐƯỢC ĐỂ GitHub Release hiển thị log commit tự động đơn lẻ như `- chore: Update appcast.xml for release`.

---

## 2. Quy Trình Release, Đồng Bộ Version & Auto-Update Qua App
- **Đồng bộ phiên bản chính xác (BẮT BUỘC cho Auto-Update):** Trước khi release bản mới, BẮT BUỘC phải đổi và kiểm tra chính xác số version mới nhất ở tất cả các vị trí để ứng dụng có thể cập nhật trực tiếp (In-App Update via Sparkle) mà không bị kẹt hoặc báo sai phiên bản:
  - `NotchPulse.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION` & `MARKETING_VERSION`)
  - `appcast.xml` (Sparkle auto-update feed XML - phải cập nhật tag `<sparkle:version>` và `<sparkle:shortVersionString>`)
  - Thẻ Release/Tag trên GitHub (ví dụ: `v3.1.2`).
  - File `RELEASE_NOTES.md` (Viết bằng tiếng Anh chuẩn cho người dùng).
- **Sparkle Auto-Update & Code Signing cho DMG:** 
  - File `NotchPulse.entitlements` phải luôn duy trì `com.apple.security.app-sandbox = false` đối với ứng dụng Mac phân phối ngoài App Store để công cụ cài đặt Sparkle (`Autoupdate.app`) có thể ghi đè bản mới vào `/Applications`.
  - Quy trình ký chữ ký số trong `build-dmg.yml` phải ký theo chuẩn inside-out (ký từng framework riêng biệt không kèm `--entitlements` của app chính) để không làm hỏng chữ ký của Sparkle.framework.

---

## 3. Quy Chuẩn Layout & Đa Màn Hình (Multi-Monitor)
- **Căn chỉnh theo Tỷ Lệ (Percentage-based):** Sử dụng tỷ lệ màn hình động thay vì hardcode pixel cứng cho các thành phần UI (Lyrics, Media View).
- **Phân biệt Màn Hình:**
  - Màn hình chính Mac: Thiết kế tối ưu theo kích thước và vị trí của Notch.
  - Màn hình ngoại vi (External Display): Thiết kế chuẩn theo màn hình phẳng, căn giữa cân đối, không áp dụng khoảng trống Notch của Mac.
- **Micro-animations & Zoom:** Khi phóng to/thu nhỏ Media View, chỉ điều chỉnh tỷ lệ rất nhỏ (1-2px) để tránh làm vỡ layout làm cho chữ Lyrics bị nhảy dòng ngoài ý muốn.

---

## 4. Lock Screen & FaceID Window
- Khi chuyển quay lại Lock Screen lúc đang làm việc: Ưu tiên chế độ rê chuột (Hover) để kích hoạt/mở khóa FaceID thay vì yêu cầu nhấn nút bấm.
