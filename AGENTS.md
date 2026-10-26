# NotchPulse Agent Instructions & Rules

Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

## ⛔️ STRICT RELEASE CONSTRAINT
If the user's prompt does **NOT** contain a direct, explicit command or request regarding releasing (such as "release", "publish", "tag", "release lại", "sửa lỗi build release", etc.), **DO NOT** bump versions or build numbers, **DO NOT** create or push git tags, and **DO NOT** trigger release workflows. Simply make code edits and verify correctness.

## 🛑 BATCH COMMITTING RULE (NO INTERMEDIATE COMMITS)
**DO NOT** create git commits after every small edit, individual step, or turn. Simply edit code, verify correctness, and leave changes in the working tree. Wait until performing a release (or when the user explicitly requests to commit) to commit all changes together in a single consolidated commit.

## 🍏 100% NATIVE MACOS & APPLE HIG DECLARATIVE UI RULES (STRICT ARCHITECTURAL REQUIREMENT)
Toàn bộ giao diện và kiến trúc UI/UX của ứng dụng BẮT BUỘC phải tuân thủ triệt để triết lý **Declarative UI** chuẩn Apple Human Interface Guidelines (HIG). Tuyệt đối **KHÔNG ĐƯỢC PHÉP** tự chế phong cách đồ họa thủ công (no custom styling, no hardcoded hex colors, no fixed blur values).

### 1. Kiến Trúc Cửa Sổ & Bố Cục Chính (Window Kinetics & Split View)
- Sử dụng cấu trúc cửa sổ native cao cấp: Cửa sổ ẩn thanh tiêu đề (`titleBarStyle: .hidden` hoặc `.windowStyle(.hiddenTitleBar)`), kết hợp `window.titlebarAppearsTransparent = true`.
- Khung sườn ứng dụng phải sử dụng `NavigationSplitView` kết hợp với `List` có `.listStyle(.sidebar)`.
- Cấu hình cửa sổ cho phép xuyên thấu (`window.isOpaque = false`, `window.backgroundColor = .clear`) để WindowServer tự kích hoạt **Sidebar Vibrancy** lấy mẫu hình nền desktop (Frosted Glass / Liquid Glass / Tahoe).
- Không được vẽ đè các lớp màu đặc (opaque) lên toàn bộ cửa sổ che mất vibrancy.

### 2. Chất Liệu Nền Phân Tầng Hệ Thống (Hierarchical System Materials)
- Mọi thành phần nền bắt buộc phải dùng các vật liệu ngữ nghĩa của Apple:
  + Nền cửa sổ lớn / detail: `.background(Color(nsColor: .windowBackgroundColor))` hoặc `.background(.window)`.
  + Nền sidebar / navigation: `.background(.sidebar)` hoặc `.listStyle(.sidebar)`.
  + Nền thanh header bám đỉnh: `.safeAreaInset(edge: .top, spacing: 0)` với `.background(.bar)`.
  + Nền các khối nội dung nổi, modal, tooltip, popover: Dùng `.background(.thickMaterial)` hoặc `.background(.regularMaterial)`.
- Hệ thống sẽ tự biến các chất liệu này thành kính khúc xạ trên macOS mới, kính mờ trên đời trung, hoặc màu phẳng đặc (Opaque) khi người dùng bật **Reduce Transparency** trong Accessibility.

### 3. Màu Sắc Ngữ Nghĩa & Tương Phản Tự Động (Semantic Color Tokens)
- **NGHIÊM CẤM** dùng mã màu Hex cố định (`#xxxxxx`) hoặc `rgba(...)` tự chế cho chữ, icon, đường kẻ.
- Phải dùng bảng màu Dynamic của hệ thống:
  + Chữ và biểu tượng chính: `.foregroundStyle(.primary)` (tự động đảo Trắng/Đen theo Light/Dark Mode).
  + Chữ mô tả phụ, chú thích: `.foregroundStyle(.secondary)`.
  + Icon phụ, nút đóng, trạng thái mờ: `.foregroundStyle(.tertiary)` hoặc `.quaternary`.
  + Trạng thái active / highlight: Dùng `.tint` hoặc `Color.accentColor` / `Color.effectiveAccent`.
  + Đường kẻ ngăn cách: Dùng `Divider()` hoặc viền `.separator` (hairline 0.5pt), hệ thống tự tính toán độ mờ và độ tương phản theo từng đời OS.

### 4. Kiểu Chữ & Biểu Tượng Hệ Thống (Dynamic Typography & SF Symbols)
- Không hardcode kích cỡ font bằng số pixel cố định tùy tiện cho các thành phần hệ thống. Sử dụng Semantic Text Styles: `.font(.title)`, `.font(.title2.weight(.bold))`, `.font(.headline)`, `.font(.body)`, `.font(.caption)`.
- Toàn bộ icon bắt buộc gọi trực tiếp từ bộ `SF Symbols` của Apple.

### 5. Cấu Trúc Khối Nội Dung Thống Nhất (Unified Grouped Content - Không Bị Chia Div Vụn)
- Trong Detail View, sử dụng `Form` với `.formStyle(.grouped)`. Các tùy chọn trong cùng một nhóm phải đặt trong `Section { ... } header: { ... }` để hệ thống tự tạo một Card bo tròn liên tục duy nhất (Continuous Rounded Card).
- Tuyệt đối không tự bọc từng dòng lẻ bằng các khối "div" hay tự vẽ viền border hộp con (blocking frames) gây vỡ vụn giao diện.

