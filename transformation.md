# 💎 NotchPulse Pure Apple Native Transformation Blueprint
> **Tài liệu Kế hoạch Chuyển đổi Toàn diện Kiến trúc & Giao diện NotchPulse đạt chuẩn Apple Native 100% (macOS Sequoia & Sonoma Pure HIG)**

---

## 🧭 1. TÔN CHỈ BẤT KHẢ XÂM PHẠM (CORE MANIFESTO)

> ⭐️ **"Tối đa Native – Không chế cháo – Tự động hòa nhập 100% với macOS"**

1. **Tuyệt đối KHÔNG chế tạo thêm tùy chọn giao diện nhân tạo (Zero Custom Toggles):**
   - Xoá bỏ hoàn toàn các nút chọn "Kính A, Kính B, hay Nền đen lì" trong Settings.
   - Ứng dụng **tự động đồng bộ 100% với hệ thống macOS**:
     - **Dark Mode**: Thân notch/card khi mở tự hoá thành kính mờ hun khói sang trọng (`.regularMaterial` / `.ultraThinMaterial` dark vibrancy), chữ và icon tự chuyển sang màu trắng tương phản chuẩn HIG (`.primary`, `.secondary`).
     - **Light Mode**: Thân notch/card khi mở tự hoá thành kính mờ băng tuyết trắng sữa trong veo, chữ và icon tự chuyển sang màu đen/xám than tương phản cao.
     - Tự động thay đổi màu nhấn theo **Accent Color** mà người dùng cài trong *System Settings > Appearance* của macOS.

2. **Quy tắc "Mỏ Neo Đen Tuyệt Đối" khi Đóng & Inline (The Black Anchor Rule):**
   - **Áp dụng cho cả Màn hình MacBook có Notch lẫn Màn hình Ngoại vi hiển thị dạng Notch**:
     - **Khi ĐÓNG (Closed):** Thân notch luôn là **Đen Tuyền Tuyệt Đối (`#000000`)** đính sát mép trên cùng màn hình (có 2 tai thỏ bo cong mềm mại ra hai bên).
     - **Khi INLINE (Mini HUD thu gọn):** Các trạng thái mini (sóng nhạc, icon pin sạc, âm lượng mini) nằm trọn trên nền đen nguyên bản để không bao giờ lộ camera hoặc viền nhựa bezel.
     - **Với Màn hình chọn kiểu Dynamic Island (Viên thuốc lơ lửng):** Lúc đóng/inline là một viên thuốc đen tuyền nhỏ gọn trôi nổi ở đỉnh.

3. **Quy tắc "Phiến Kính Native Siêu Nét" khi MỞ RỘNG (The Liquid Expanded Drawer):**
   - Khi hover hoặc click để mở bung Notch:
     - **Màn hình hiển thị dạng NOTCH (MacBook hoặc Màn ngoài):** Cục tai thỏ ở đỉnh mép trên **VẪN GIỮ NGUYÊN CỤC ĐEN** làm điểm neo (Camera Anchor) che mắt camera vật lý/mép viền. Chỉ có **toàn bộ phần thân mở rộng trượt xuống bên dưới** mới biến đổi thành **Phiến kính Native (`NSVisualEffectView` / SwiftUI Material)**.
     - **Màn hình hiển thị dạng DYNAMIC ISLAND (Viên thuốc nổi):** Toàn bộ viên thuốc nở to ra thành một tấm thẻ kính mờ trôi nổi đối xứng bốn góc.
   - Bao quanh phiến kính là đường viền tóc chuẩn Apple (`strokeBorder(Color.white.opacity(0.12))` ở Dark Mode và `Color.black.opacity(0.08)` ở Light Mode), tạo chiều sâu lơ lửng đẳng cấp.

4. **Bí thuật Vibrancy & Hiển thị Sắc nét Tuyệt đối (Apple Optical Vibrancy):**
   - Không dùng màu bệt phẳng (`Color.white` hay `Color(white: 0.10)`).
   - Dùng 100% cơ chế **Vibrancy Native của Apple** để trích xuất ánh sáng từ hình nền phía sau, tự động khử răng cưa Sub-pixel cho màn hình Retina, đảm bảo mọi dòng chữ, icon, thanh trượt luôn **sắc sảo, sáng rõ, không bao giờ bị nhoè, đục hay chìm màu**.

5. **Bài học Xương máu từ Thử nghiệm Cũ (Lessons Learned & Anti-Patterns):**
   - ❌ **Không dùng Gradient màu đè lên mép (Cutout Artifact):** Tuyệt đối không dùng `LinearGradient(colors: [Color.black, .clear])` đè lên thanh cuộn ngày Calendar hay danh sách. Trên nền kính xám, việc đè màu đen tạo ra 2 khối chữ nhật đen xì thô kệch. Phải dùng **`.mask(LinearGradient(stops: ...))`** để tác động vào kênh Alpha độ trong suốt của chính nội dung.
   - ❌ **Không nhét hộp lồng trong hộp (Nested Boxy Syndrome):** Tránh đóng khung Music Player thành một hộp xám đục riêng biệt bên trong Notch. Học tập Apple Control Center: tất cả các widget nằm trên **cùng một mặt phẳng kính quang học chung (Unified Surface Material)**, phân tách bằng khoảng thở (spacing) và độ sáng nền nhẹ (`Color.primary.opacity(0.12)`), không tạo khung viền hộp rời rạc.
   - ❌ **Không gán màu cứng (No Hardcoded Hex/RGB):** Không dùng `Color(white: 0.65)` hay các mã màu tĩnh khiến chữ bị "bết" màu. 100% chữ và biểu tượng dùng Semantic Typography (`.primary`, `.secondary`, `.tertiary`).

---

## 🏗️ 2. KIẾN TRÚC THỊ GIÁC: NOTCH vs DYNAMIC ISLAND

### A. MÀN HÌNH HIỂN THỊ DẠNG NOTCH (MacBook & Màn hình ngoài chọn Notch)
```
1. TRẠNG THÁI ĐÓNG (CLOSED):
   ┌────────────────────────────────┐
   │     █ █ █ █ █ █ █ █ █ █ █      │  <- ĐEN TUYỀN 100% (#000000)
   └────────────────────────────────┘     Gắn sát mép trên, hòa vào viền máy.

2. TRẠNG THÁI INLINE MINI (INLINE HUD):
   ┌────────────────────────────────┐
   │ 🔊 50%  █ █ Camera █ █  🔋 98% │  <- VẪN GIỮ NỀN ĐEN 100%
   └────────────────────────────────┘     Chữ và icon trắng nhỏ gọn gắn 2 bên tai.

3. TRẠNG THÁI MỞ RỘNG (EXPANDED):
   ┌────────────────────────────────┐
   │ █ █ █ █ Camera Anchor █ █ █ █  │  <- VẪN GIỮ NGUYÊN CỤC ĐEN Ở ĐỈNH
   │────────────────────────────────│
   │                                │  <- THÂN NỞ RỘNG: KÍNH MỜ NATIVE
   │     TỰ ĐỘNG THEO HỆ THỐNG:     │     - Tự động mờ sương theo Dark/Light
   │   - Khúc xạ hình nền Desktop   │     - Chữ & Icon tự nổi sắc nét (Vibrancy)
   │   - Viền phản xạ ánh sáng mảnh │     - 100% Metal GPU tăng tốc, 120Hz
   │                                │
   └────────────────────────────────┘
```

### B. MÀN HÌNH HIỂN THỊ DẠNG DYNAMIC ISLAND (Viên thuốc nổi)
```
1. TRẠNG THÁI ĐÓNG / INLINE:
   ╭────────────────────────────╮
   │ 🔊 50%  NotchPulse   🔋 98% │  <- VIÊN THUỐC ĐEN NỔI LƠ LỬNG
   ╰────────────────────────────╯     Đổ bóng nhẹ, cách mép trên một khoảng.

2. TRẠNG THÁI MỞ RỘNG (EXPANDED):
   ╭────────────────────────────────╮
   │                                │  <- TOÀN BỘ NỞ THÀNH THẺ KÍNH TRÔI NỔI
   │   PHIẾN KÍNH LIQUID NATIVE     │     - Bo cong 4 góc đối xứng hoàn hảo
   │   - Tự động theo Dark/Light    │     - Không cần cục đen che đỉnh
   │   - Hiển thị siêu sắc nét      │     - Viền bắt sáng siêu mỏng
   │                                │
   ╰────────────────────────────────╯
```

---

## 🔒 3. HOẠT ẢNH THẢ FACE ID TOÀN DIỆN TỪ VIỀN TRÊN (`y = 0`)

> ⭐️ **Quy tắc Bắt buộc:** Khi Face ID quét nhận diện, mở rộng sang 3 bên hoặc thả xuống, hoạt ảnh phải bắt đầu thả **FULL TỪ MÉP VIỀN TRÊN CÙNG CỦA MÀN HÌNH (`y = 0`)**, phủ trùm qua notch vật lý rồi mới tràn xuống/sang hai bên.

1. **Khắc phục lỗi đứt gãy trước đây:**
   - Trước đây hoạt ảnh thả Face ID chỉ bắt đầu từ chân mép dưới của notch vật lý (`y = notchHeight`), tạo cảm giác như một chiếc ngăn kéo rời rạc rơi ra từ đáy notch.
   - **Chuẩn Native Apple:** Toàn bộ khối hình học thả xuống phải bắt đầu từ tọa độ `y = 0` (mép trên cùng tuyệt đối của màn hình). Lớp đen và lớp kính lỏng bao bọc trùm qua cả notch vật lý tạo thành **một khối thống nhất không có đường chia cắt**.
2. **Hình học Thả Sang 3 Bên (Tri-Directional Sweep):**
   - **Mép trên:** Neo chặt tại `y = 0`.
   - **Cánh trái & Cánh phải:** Tràn mượt mà sang 2 bên tai thỏ với đường cong bo tròn liên tục (Continuous Spline Curves).
   - **Đáy dưới:** Hạ xuống bằng lò xo vật lý (`.interpolatingSpring(stiffness: 300, damping: 24)`), tự động co giãn theo trạng thái quét camera hoặc mở khoá thành công.

---

## 🎵 4. CHUẨN HOÁ TRÌNH PHÁT NHẠC LOCK SCREEN (LOCK SCREEN MEDIA - 100% APPLE DECIDED)

> ⭐️ **Tôn chỉ:** Xoá bỏ hoàn toàn hiện tượng thẻ nhạc bị **trắng đục** ở Light Mode hoặc **đen xì tuyệt đối** ở Dark Mode do gán màu chết (`Color.white` / `Color.black`). Mọi độ trong suốt, tán sắc và độ mờ của thẻ Lock Screen Media **100% do engine quang học của Apple quyết định**!

1. **Vật liệu Quang học Tự động theo Hệ điều hành (System Optical Material):**
   - Sử dụng trực tiếp `NSVisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)` hoặc `.ultraThinMaterial` của SwiftUI.
   - **Tự động phản hồi theo hình nền Lock Screen:** Dù người dùng dùng ảnh tĩnh hay Dynamic Video Wallpaper (macOS Sonoma / Sequoia), phiến kính tự động trích xuất màu sắc và khúc xạ chuyển động phía sau mà không cần code bất kỳ bộ lọc màu giả lập nào.
   - Không chèn thêm bất kỳ background màu đục nào: Không `Color.white.opacity(...)`, không `Color.black.opacity(...)`.
2. **Compact Player Card (Thẻ Mini ở Màn hình Khoá):**
   - Bo góc mềm mại `RoundedRectangle(cornerRadius: 24, style: .continuous)`.
   - Đường viền tóc chuẩn Apple: Viền sáng phản quang siêu mỏng `0.75pt` bắt sáng theo nguồn sáng của hình nền.
   - Typography dùng `.primary` (tự động đảo màu sáng/tối với độ tương phản cao) và `.secondary` cho tên nghệ sĩ.
   - Neo cố định trên màn hình chính, không giật theo chuột khi sử dụng đa màn hình.
3. **Full-Screen Immersive Player (Chế độ Phóng to Toàn màn hình):**
   - Giữ nền Ambient Blur phóng to từ ảnh bìa album art.
   - Cột lời bài hát hiển thị font SF Pro Rounded cỡ lớn, dòng đang hát sáng rực rỡ, dòng chưa hát mờ dần chuẩn Apple Music Sing.

---

## ⚙️ 5. CHUẨN HÓA CỬA SỔ CÀI ĐẶT (SETTINGS - 100% APPLE HIG COMPLIANT)

> ⭐️ **Tôn chỉ:** Cửa sổ Settings phải mang lại cảm giác **như một phân hệ gốc được tích hợp sâu trong System Settings của Apple**, không còn bất kỳ dấu vết nào của giao diện chế cháo (Zero Ad-hoc UI).

```
┌──────────────────────────────────────────────────────────────┐
│ [● ● ●]  Settings                               (Search Bar) │ <- macOS Native Unified Window Toolbar
├───────────────┬──────────────────────────────────────────────┤
│ ⚙️ General     │  ┌────────────────────────────────────────┐  │
│ 🎨 Appearance  │  │ [✨ Tính năng & Giới thiệu]          > │  │ <- macOS Inset Grouped Section Card
│ 🎵 Media       │  └────────────────────────────────────────┘  │    (Bo góc viền kính mờ tự nhiên)
│ 📅 Calendar    │  ┌────────────────────────────────────────┐  │
│ 🔒 Face ID     │  │ Khởi động cùng Mac           [ Bật ]  │  │ <- Native Toggle / Controls
│ 📊 Stats       │  │ Tự động kiểm tra bản mới     [ Bật ]  │  │
│ 💨 Fan & SMC   │  └────────────────────────────────────────┘  │
│ (Sidebar Kính)│  (100% Responsive theo Dark/Light macOS)    │
└───────────────┴──────────────────────────────────────────────┘
```

1. **Thanh Toolbar Hệ thống Thống nhất (Unified Window Toolbar):**
   - Xóa bỏ hoàn toàn thanh `SettingsDetailHeaderBar` tự chế.
   - Sử dụng Window Toolbar chuẩn SwiftUI với Window Titlebar trong suốt (`titlebarAppearsTransparent = true`, `fullSizeContentView`).
   - Tích hợp ô tìm kiếm native `.searchable(...)` để tìm kiếm cài đặt tức thì.
2. **Sidebar Kính Mờ Chuẩn Apple (Native Navigation Sidebar):**
   - Sử dụng `NavigationSplitView` với kiểu `SidebarListStyle()`, nền kính `sidebar` native của AppKit.
   - Các danh mục hiển thị với SF Symbol đặt trong ô vuông bo góc màu tròn trịa (như icon Wi-Fi, Bluetooth, Màn hình trong System Settings của macOS).
3. **Bố cục Thẻ Nhóm Inset Grouped (`.formStyle(.grouped)`):**
   - Các mục cài đặt được gom vào các `Section` bo cong góc chuẩn (`cornerRadius: 10, style: .continuous`), đường kẻ ngăn cách (separator) tự động thụt lề theo chuẩn HIG.
   - Toàn bộ nền form phản hồi 100% theo Dark Mode / Light Mode của macOS mà không cần gán cứng màu sắc.
4. **Kiểm soát Tương tác 100% Native Controls:**
   - Các nút Toggle, Slider, Dropdown Picker, Stepper dùng 100% component gốc của Apple.
   - Màu nhấn (Accent Color) của Toggle và Slider tự động ăn khớp với màu người dùng chọn trong *System Settings > Appearance*.

---

## 🧩 6. NÂNG CẤP CÁC LINH KIỆN NỘI BỘ NOTCH (COMPONENTS)

Loại bỏ toàn bộ các khối màu đen thô cứng bên trong thân notch khi mở rộng, chuyển sang linh kiện native:

| Thành phần | Hiện tại (Custom cũ) | Thiết kế Pure Native Mới |
| :--- | :--- | :--- |
| **Thanh chuyển Tab** | Các viên thuốc `Capsule().fill(.black)` tự vẽ, viền sắc cạnh. | Thanh phân đoạn (Segmented Control) kính mờ, icon tự động bắt sáng khi active. |
| **Thanh trượt (Slider)** | Tự vẽ hình chữ nhật màu xanh/cam cố định bằng DragGesture. | Thanh trượt Capsule kính mờ viền sáng chuẩn Apple, có độ nảy lò xo tự nhiên khi kéo chạm biên. |
| **Trình phát Nhạc (Media)** | Khung nền đen đè lên. | Bề mặt kính mờ khúc xạ nhẹ màu sắc của bìa album (Dynamic Ambient Tinting) mà không dùng hộp đen. |
| **Lịch Âm & Dương** | Bảng vuông nền đen lì. | Lịch kính mờ, ngày hiện tại tự động dùng màu nhấn hệ thống (`Color.accentColor`), mép dùng `.mask` alpha. |
| **Kệ File & Clipboard** | Các ô xám đặc. | Ô kính mờ nhận diện dạng tệp, hover có hiệu ứng sáng viền mềm mại. |
| **Văn bản & Biểu tượng** | Ép chết màu trắng hoặc màu xám hex. | Dùng màu ngữ nghĩa hệ thống: `.primary`, `.secondary`, `.tertiary` để luôn hiển thị sắc sảo ở cả Light Mode lẫn Dark Mode. |

---

## 🛡️ 7. QUY TẮC AN TOÀN BẤT KHẢ XÂM PHẠM (GOLDEN RULES)

Khi thực thi mã nguồn, **bắt buộc tuân thủ 100%** các quy tắc sau:

1. **Bảo toàn Hoạt ảnh Đóng/Mở (Animation Continuity):**
   - **TUYỆT ĐỐI CẤM** dùng cấu trúc `if vm.notchState == .open { ... } else { ... }` ở lớp vỏ ngoài của Notch. Việc tráo đổi danh tính View (View Identity Swap) sẽ gây hiện tượng vỡ khung hình hoặc mở giật bụp.
   - Phải sử dụng phép biến đổi liên tục (Continuous Interpolation) cho lớp nền:
     ```swift
     // Khi đóng: đen 100%. Khi mở: hòa vào vật liệu kính mờ tự nhiên
     .background(
         ZStack {
             if vm.notchState == .closed {
                 Color.black
             } else {
                 Rectangle().fill(.ultraThinMaterial)
             }
         }
     )
     ```
2. **Quy tắc đối xứng hình học 14px:**
   - Luôn duy trì padding ngang đối xứng tuyệt đối giữa trạng thái đóng và mở để khi co giãn notch không bị giật sang hai bên.
3. **Face ID Top-Most Layer & Mép Viền y = 0:**
   - Hệ thống camera Face ID và hoạt ảnh nhận diện luôn nằm ở lớp cao nhất (`.zIndex(999)`), neo thả từ `y = 0` phủ trùm qua notch vật lý để đảm bảo tính liền mạch.
4. **Không làm tăng tải hệ thống (Performance First):**
   - Tận dụng tối đa bộ kết xuất phần cứng Metal của Apple có sẵn trong `NSVisualEffectView` / `Material`.
   - Mức tiêu thụ RAM duy trì ở mức siêu nhẹ (~35–50MB), đảm bảo tần số quét 120Hz mượt mà trên màn hình ProMotion.

---

## 🚀 8. LỘ TRÌNH THỰC THI (IMPLEMENTATION PHASES)

```mermaid
graph TD
    P1[Giai đoạn 1: Chuẩn hóa Cửa sổ Cài đặt Settings 100% HIG] --> P2[Giai đoạn 2: Nâng cấp Kính Mờ Lock Screen Media Phản hồi Apple]
    P2 --> P3[Giai đoạn 3: Face ID Drop y=0 & Liquid Material Engine cho Thân Notch]
    P3 --> P4[Giai đoạn 4: Nâng cấp linh kiện bên trong Notch]
    P4 --> P5[Giai đoạn 5: Kiểm thử hiển thị Dark/Light Mode & 120Hz]
```

### 📍 Giai đoạn 1: Chuẩn hóa Cửa sổ Settings (Pure HIG)
- [ ] Xóa bỏ `SettingsDetailHeaderBar` tự chế.
- [ ] Chuyển các tab cài đặt sang cấu trúc thẻ Inset Grouped (`.formStyle(.grouped)`).
- [ ] Dùng Sidebar List Style với các icon SF Symbol chuẩn hệ thống.
- [ ] Đồng bộ hóa màu chữ, thanh trượt và toggle theo bảng màu hệ thống macOS.
- [ ] Đảm bảo Settings hiển thị hoàn hảo trên cả Dark Mode và Light Mode.

### 📍 Giai đoạn 2: Nâng cấp Kính Mờ Native cho Lock Screen Media
- [ ] Loại bỏ hoàn toàn màu nền trắng bệt/đen đục gán cứng trong `LockScreenMediaView.swift`.
- [ ] Tích hợp `NSVisualEffectView` / `.ultraThinMaterial` để độ kính mờ 100% do engine quang học Apple quyết định dựa trên hình nền khoá.
- [ ] Bổ sung viền tóc phản quang mỏng bo cong góc 24px.
- [ ] Typography chuẩn `.primary` / `.secondary` tự động phản hồi độ tương phản quang học.

### 📍 Giai đoạn 3: Face ID Drop y = 0 & Liquid Material Engine cho Notch
- [ ] Hoạt ảnh thả Face ID phủ trùm từ đỉnh màn hình `y = 0` xuống và sang 3 bên không đứt gãy.
- [ ] Cập nhật [ContentView.swift](file:///Users/hieukunn/Learning%20ITM/My%20project/NotchPulse/NotchPulse/ContentView.swift): Tích hợp lớp nền chuyển đổi Đóng (Black Anchor) -> Mở (Native Material).
- [ ] Duy trì cụm đen che đỉnh camera vật lý khi ở kiểu Notch (cả màn MacBook và màn ngoài).
- [ ] Thêm đường viền tóc phản quang mảnh chuẩn Apple bao quanh thân mở rộng.

### 📍 Giai đoạn 4: Nâng cấp Linh kiện bên trong Notch
- [ ] Chuyển đổi Card nhạc, Bảng lịch, Ngăn quạt tản nhiệt, Kệ file sang vật liệu kính mờ.
- [ ] Calendar ngày cuộn dùng `.mask(LinearGradient(stops: ...))` thay thế hoàn toàn gradient đen cũ.
- [ ] Thay thế các nút Tab bọc đen lì sang thanh phân đoạn kính mờ tinh tế.
- [ ] Thay thế thanh trượt Volume / Brightness / Fan sang Capsule chuẩn hệ thống.

### 📍 Giai đoạn 5: Kiểm thử và Hoàn thiện
- [ ] Test thực tế khi đổi hình nền Desktop (sáng, tối, rực rỡ, ảnh phong cảnh).
- [ ] Test chuyển đổi qua lại giữa Light Mode và Dark Mode trong System Settings.
- [ ] Kiểm tra độ mượt 120Hz ProMotion và theo dõi RAM/CPU không bị rò rỉ.

---

*Bản kế hoạch này là kim chỉ nam tối thượng cho quá trình đưa NotchPulse trở thành ứng dụng Native đỉnh cao nhất trên macOS.*
