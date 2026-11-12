/**
 * NotchPulse Landing Page Controller
 * Features:
 * - Pure Apple Dark Aesthetic
 * - Scroll-Triggered Fade-In Animations (IntersectionObserver)
 * - Complete English & Vietnamese bilingual localization (i18n)
 * - 3D Mouse Tilt & Parallax effects
 * - Interactive Dynamic Island & MacBook Notch Simulator
 * - Multilingual & Diverse Customer Reviews Filter (5★, 4.5★, 4★, 3.5★)
 * - 1-Click Homebrew command copy with toast feedback
 */

// =============================================================================
// Localization Dictionary (EN / VI / DE / JA / ZH-TW / ZH-CN / FR / ES / AR)
// =============================================================================

const i18nData = {
  en: {
    // Navigation
    "nav.skip": "Skip to main content",
    "nav.features": "Features",
    "nav.demo": "Live Demo",
    "nav.reviews": "Reviews",
    "nav.creator": "Creator",
    "nav.download": "Download",
    "nav.get": "Get App (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} Released",
    "hero.title": "MacBook Notch, Reimagined.",
    "hero.titleMain": "MacBook Notch,",
    "hero.titleAccent": "Reimagined.",
    "hero.subtitle": "Transform your MacBook camera notch into a fluid, 120Hz ProMotion Dynamic Island. Includes classic Launchpad Home for modern macOS, ultra-smooth 60Hz HUDs, Biometric Face ID, Lock Screen Live Player, and universal browser media controls.",
    "hero.downloadBtn": "Download NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Verified",
    "chip.faceidSub": "On-Device Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "Classic Grid • F4 & Pinch",
    "chip.hudTitle": "Smooth 60Hz HUDs",
    "chip.hudSub": "Volume, Brightness & Keylight",
    "chip.settingsTitle": "Native HIG Settings",
    "chip.settingsSub": "Live Search & Feature Tour",
    "chip.ddcTitle": "DDC Display Control",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Active",
    "chip.batterySub": "Smart 80% Limit Protected",
    "chip.shelfTitle": "Notch Shelf Ready",
    "chip.shelfSub": "Drag & Drop + AirDrop Share",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU Idle Overhead",
    "chip.lyricsTitle": "Browser & Music Sync",
    "chip.lyricsSub": "Spotify, Music, YouTube & Web",
    "chip.statsTitle": "System Monitor",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "Clipboard History",
    "chip.clipboardSub": "50 Items • Quick ⌘⌥V",
    "chip.lunarTitle": "Lunar & Multi-Cal",
    "chip.lunarSub": "Âm Lịch • Hijri • Hebrew",
    "chip.islandTitle": "Dynamic Island Mode",
    "chip.islandSub": "Pixel-Perfect Bezier Curve",
    "chip.lockscreenTitle": "Lock Screen Player",
    "chip.lockscreenSub": "Live Controls & Lyrics",
    "chip.displayTitle": "Multi-Display Hub",
    "chip.displaySub": "Dual Screen Seamless Sync",

    // Demo Controls & Notch
    "demo.modeNotch": "MacBook Notch",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Synced Lyrics",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "Notch Shelf",
    "demo.hint": "Click or hover over the notch above to trigger 120Hz fluid expansion!",
    "notch.idle": "NotchPulse Active",
    "notch.faceIdScanned": "Face ID Verified",
    "notch.faceIdPrompt": "Mac unlocked seamlessly via front camera",
    "notch.batteryPrompt": "Full in 18 minutes • Battery Health: 100%",
    "notch.shelfItems": "Shelf: 3 Items",
    "notch.shelfPrompt": "Drop files into notch to stash temporarily",

    // Bento Features Section
    "features.tag": "Engineered for macOS",
    "features.title": "Supercharge Your MacBook Notch",
    "features.subtitle": "Built natively in Swift with 0% CPU overhead at idle. Experience Launchpad Home, smooth 120Hz ProMotion & 60Hz HUDs, biometric Face ID, Lock Screen Live Player, and smart desktop tools.",
    
    "feat1.title": "Biometric Face ID Recognition",
    "feat1.desc": "Brings iOS-grade facial recognition to your Mac. Continuously senses your presence, previews camera status smoothly, and unlocks protected apps with privacy-first on-device Apple Vision processing.",
    "bento.faceidVerified": "Neural Face Mesh Active",
    "bento.faceidSub": "512D Vector Embedding • On-Device Apple Vision",
    "bento.faceidHandshake": "Lock Screen to Active Desktop Zero-Lag Handshake",

    "feat2.title": "120Hz ProMotion Dual Mode",
    "feat2.desc": "Fluidly morphs between native MacBook Notch profile and a centered floating Dynamic Island on external Studio Displays.",
    "bento.springPhysics": "Spring Physics (response: 0.38s)",

    "feat3.title": "Live Synced Lyrics & Universal Media",
    "feat3.desc": "Live word-by-word streaming lyrics and playback controls for Spotify, Apple Music, YouTube Music, and web browsers (YouTube, Netflix on Safari, Chrome & Arc) with direct timeline seek and vibrant artwork.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf & Quick Drop",
    "feat4.desc": "Drag files, links, or screenshots directly into the notch bezel to hold them temporarily across workspaces and apps.",
    "shelf.dropText": "Drop files here",

    "feat5.title": "Multi-Display Hub & DDC Hardware HUD",
    "feat5.desc": "Control built-in and external monitor hardware brightness and audio volume from a unified Display Hub or via DDC/CI with cursor-aware F1/F2 keys and 2.2ms write coalescing.",
    "bento.ddcBrightness": "Dell UltraSharp 4K Brightness",
    "bento.ddcVolume": "Built-in Audio Volume",

    "feat6.title": "Live CPU, RAM & GPU System Monitor",
    "feat6.desc": "Real-time hardware telemetry directly inside the notch. Track Apple Silicon unified memory pressure, CPU core clusters, and GPU load with 0% idle overhead.",
    "bento.cpuCores": "8 Cores Active",
    "bento.ramUsage": "10.3 / 16 GB Active",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "Regional Lunar & Multi-Country Calendar",
    "feat7.desc": "Astronomical offline calculation for Vietnamese Lunar (UTC+7, Dr. Ho Ngoc Duc), Chinese Nongli (UTC+8), Islamic Hijri, Hebrew, Buddhist, and Persian systems. Interactive Moon button reveals daily lunar dates under full month grid.",
    "feat7.monthTitle": "September 2026",
    "feat7.moonBadge": "Lunar Cal",
    "feat7.eventBadge": "Sep 27 (17/8 Lunar Cal)",
    "feat7.eventTitle": "NotchPulse Product Launch",
    "feat7.eventTime": "19:00 - 20:30 • All Day Sync",

    "feat8.title": "Smart 80% Battery Health Guard",
    "feat8.desc": "Direct Apple Silicon SMC power controller. Caps charging at the 80% sweet spot to preserve battery cycle longevity, with one-tap 100% boost.",

    "feat9.title": "Smart Clipboard Manager & Stash",
    "feat9.desc": "Comfortable 3-item viewport, instant search, and AppKit scroll bounds protection. Copy snippets, hex colors, and formatted text directly from the notch.",

    "feat10.title": "9-Language Native Localization",
    "feat10.desc": "Full native localized interface across English, Tiếng Việt, 繁體中文, 简体中文, 日本語, Deutsch, Français, Español, and العربية with real-time UI switching.",

    "feat11.title": "Native SMC Fan & Thermal Control",
    "feat11.desc": "Direct SMC hardware driver with auto root authorization. Control fan speeds (Auto, Max Blast, Silent, Custom RPM) and monitor CPU/GPU thermal sensors directly from the notch.",

    "feat12.title": "Interactive Audio Hub & Bluetooth Battery",
    "feat12.desc": "Switch audio outputs and microphones directly inside the notch. Manage individual per-app volume sliders and track AirPods & Bluetooth headphone battery levels in real time.",
    "bento.audioOutputs": "AirPods Pro • 92% Battery",
    "bento.audioApps": "Per-App Audio Mixer • Spotify & Safari",
    "bento.audioTabOutput": "Output",
    "bento.audioTabInput": "Input",

    "feat13.title": "macOS System Auth & Hands-Free Face ID",
    "feat13.desc": "Intercepts administrative sudo prompts, Keychain credential requests, and Touch ID dialogs across macOS. Seamlessly authenticates with privacy-first on-device Apple Vision without typing passwords.",
    "bento.authIntercept": "Terminal sudo & Keychain Intercept",
    "bento.authFaceID": "Apple Vision Biometric Verification",
    "bento.authStatus": "Authenticated Hands-Free",

    "bento.fanRpm": "4,800 RPM Turbo",
    "bento.fanCpuTemp": "CPU 42°C • Cool & Quiet",
    "bento.fanRootAuth": "Auto Root Daemon Active",

    "feat14.title": "Launchpad Home for Modern macOS",
    "feat14.desc": "Restores the classic full-screen paged app grid on every macOS version. Features mouse drag & two-finger swipe paging, folders, instant notch search, edge-to-edge 4K/5K display scaling, and deep interception of F4 keys, Hot Corners, Dock & pinch gestures.",
    "bento.lpSearch": "Search apps & folders (⇧⌘L)",
    "bento.lpTabPage1": "Page 1",
    "bento.lpTabPage2": "Page 2",
    "bento.lpTabFolder": "Folder",
    "bento.lpFolderUtilities": "Dev Tools",
    "bento.lpBadgeScaling": "4K/5K Edge-to-Edge Scaling",
    "bento.lpBadgeIntercept": "F4 • Hot Corner • 4-Finger Pinch",

    "feat15.title": "Ultra-Smooth 60Hz Hardware HUDs",
    "feat15.desc": "Replaces macOS Volume, Brightness, Keyboard Backlight, and MagSafe Power HUDs without duplicate overlays. Features 60Hz continuous key-hold interpolation, interactive notch bar scrubbing, plus Inline & Open Notch styles.",
    "bento.hudVolumeLabel": "Volume",
    "bento.hudBrightLabel": "Brightness",
    "bento.hudRampBadge": "60Hz Key-Hold Ramp",
    "bento.hudInlineBadge": "Inline & Scrubbing",

    "feat16.title": "Lock Screen Live Player & Browser Control",
    "feat16.desc": "Displays full interactive album art, playback controls, and on-demand synced lyrics directly on the macOS Lock Screen. Seamlessly controls YouTube, Netflix, Safari, Chrome, Arc, Spotify & Apple Music with automatic Lock-to-Desktop session sync.",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "Lock Screen HUD & On-Demand Lyrics",

    "feat17.title": "Native macOS HIG Settings & Deep Search",
    "feat17.desc": "Crafted with Apple Human Interface Guidelines: translucent NavigationSplitView sidebar vibrancy, automatic Light/Dark appearance, grouped inset cards, real-time NSSearchField spotlight highlighting, and an interactive Feature Tour.",
    "bento.higSearch": "⌘ Search 582 settings...",
    "bento.higRow1": "F4 & Pinch Intercept",
    "bento.higRow2": "Feature Tour Spotlight",
    "bento.higBadge": "Zero-Lag HIG",

    // Reviews Section
    "reviews.tag": "Global Community",
    "reviews.title": "Loved by People Worldwide",
    "reviews.subtitle": "Real feedback from Mac engineers, designers, and creators across the globe with diverse ratings.",
    "reviews.all": "All Reviews (4.8 ★)",
    "reviews.five": "5 Stars",
    "reviews.fourPointFive": "4.5 Stars",
    "reviews.four": "4 Stars",

    // Creator Section
    "creator.tag": "Meet The Creator",
    "creator.bio": "ITM student with a deep passion for system design and native macOS architectures. Built NotchPulse from scratch to explore human-computer interaction and make the MacBook notch genuinely delightful and functional.",

    // Installation Section
    "install.tag": "Ready to Elevate Your Mac?",
    "install.title": "Get NotchPulse Today",
    "install.subtitle": "Compatible with all macOS versions (macOS Monterey, Ventura, Sonoma, Sequoia & newer). Optimized for all Mac devices (Apple Silicon & Intel Macs).",
    "install.btnDmg": "Download NotchPulse.dmg (Direct)",

    // Footer
    "footer.rights": "© 2026 NotchPulse by Kun Nguyen (HieuKun). All rights reserved.",
    "footer.releases": "Releases",
    "footer.support": "Support",

    // Toast
    "toast.copied": "Homebrew command copied to clipboard!",

    // Hugo / Hani Learning
    "hugo.tag": "Featured Friend Project • Hani Chinese Learning",
    "hugo.sub": "Modern Chinese learning platform founded by Do Manh Hung (Hugo)",
    "hugo.btn": "Register & Get 2,000 Hani Coins"
  },

  vi: {
    // Navigation
    "nav.skip": "Chuyển đến nội dung chính",
    "nav.features": "Tính Năng",
    "nav.demo": "Demo Trực Tiếp",
    "nav.reviews": "Đánh Giá Quốc Tế",
    "nav.creator": "Tác Giả",
    "nav.download": "Tải Xuống",
    "nav.get": "Tải Ngay (DMG)",

    // Hero
    "hero.badge": "Đã ra mắt NotchPulse {version}",
    "hero.title": "Tai Thỏ MacBook, Tái Định Nghĩa.",
    "hero.titleMain": "Tai Thỏ MacBook,",
    "hero.titleAccent": "Tái Định Nghĩa.",
    "hero.subtitle": "Biến phần khuyết camera trên MacBook thành Dynamic Island 120Hz ProMotion mượt mà. Tích hợp Launchpad Home cho macOS mới, HUD phần cứng 60Hz siêu mượt, Face ID, Trình phát Màn hình khóa & Điều khiển nhạc trình duyệt.",
    "hero.downloadBtn": "Tải Trực Tiếp NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Sẵn Sàng",
    "chip.faceidSub": "Nhận diện khuôn mặt Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "Lưới Cổ Điển • Phím F4 & Chụm Tay",
    "chip.hudTitle": "HUD Phần Cứng 60Hz",
    "chip.hudSub": "Âm Lượng, Độ Sáng & Đèn Phím",
    "chip.settingsTitle": "Cài Đặt Chuẩn HIG",
    "chip.settingsSub": "Tìm Kiếm Nhanh & Hướng Dẫn",
    "chip.ddcTitle": "Điều Khiển Màn Hình DDC",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "Sạc MagSafe 98W",
    "chip.batterySub": "Bảo vệ pin thông minh 80%",
    "chip.shelfTitle": "Notch Shelf Sẵn Sàng",
    "chip.shelfSub": "Kéo thả + Chia sẻ AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU khi chạy nền",
    "chip.lyricsTitle": "Nhạc & Trình Duyệt",
    "chip.lyricsSub": "Spotify, Apple Music & Web",
    "chip.statsTitle": "Giám Sát Hệ Thống",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "Bộ Nhớ Tạm",
    "chip.clipboardSub": "50 Mục • Nhấn ⌘⌥V",
    "chip.lunarTitle": "Lịch Âm & Đa Lịch",
    "chip.lunarSub": "Âm Lịch VN • Hồi Giáo • Do Thái",
    "chip.islandTitle": "Chế Độ Dynamic Island",
    "chip.islandSub": "Đường Cong Bezier Hoàn Hảo",
    "chip.lockscreenTitle": "Trình Phát Màn Hình Khóa",
    "chip.lockscreenSub": "Lời Nhạc & Điều Khiển Trực Tiếp",
    "chip.displayTitle": "Đồng Bộ Đa Màn Hình",
    "chip.displaySub": "Hoạt Động 1 Notch Chuẩn Xác",

    // Demo Controls & Notch
    "demo.modeNotch": "Tai Thỏ",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Lời Nhạc",
    "demo.pillBattery": "Sạc 98W",
    "demo.pillShelf": "Notch Shelf",
    "demo.hint": "Nhấp chuột hoặc rê vào tai thỏ phía trên để trải nghiệm mở rộng 120Hz siêu mượt!",
    "notch.idle": "NotchPulse Đang Hoạt Động",
    "notch.faceIdScanned": "Đã Xác Thực Face ID",
    "notch.faceIdPrompt": "Mở khoá máy Mac an toàn qua camera trước",
    "notch.batteryPrompt": "Đầy pin sau 18 phút • Tình trạng pin: 100%",
    "notch.shelfItems": "Ngăn Chứa: 3 Tệp",
    "notch.shelfPrompt": "Kéo tệp vào tai thỏ để lưu tạm giữa các ứng dụng",

    // Bento Features Section
    "features.tag": "Tối Ưu Riêng Cho macOS",
    "features.title": "Đánh Thức Sức Mạnh Tai Thỏ",
    "features.subtitle": "Viết bằng Swift thuần túy, 0% CPU khi chạy nền. Đầy đủ Launchpad Home, HUD 60Hz siêu mượt, Face ID sinh trắc học, Trình phát Màn hình khóa & bộ công cụ thông minh.",
    
    "feat1.title": "Mở Khoá Face ID Sinh Trắc Học",
    "feat1.desc": "Mang trải nghiệm nhận diện khuôn mặt chuẩn iPhone lên máy Mac. Tự động cảm biến hiện diện, xem trước camera mượt mà và mở khóa ứng dụng an toàn với Apple Vision ngay trên thiết bị.",
    "bento.faceidVerified": "Mô Hình Lưới Face Mesh Kích Hoạt",
    "bento.faceidSub": "Véc-tơ 512D • Apple Vision trên thiết bị",
    "bento.faceidHandshake": "Mở khoá tức thì không độ trễ từ Màn hình khoá",

    "feat2.title": "Chế Độ Kép 120Hz Notch & Island",
    "feat2.desc": "Tự động chuyển đổi linh hoạt giữa màn hình tai thỏ MacBook Pro và màn hình ngoài Studio Display ở tần số 120Hz ProMotion.",
    "bento.springPhysics": "Vật lý lò xo Apple (độ trễ: 0.38s)",

    "feat3.title": "Lời Bài Hát Đồng Bộ & Nhạc Trình Duyệt",
    "feat3.desc": "Hiển thị lời bài hát chạy từng chữ thời gian thực và điều khiển phát cho Spotify, Apple Music, YouTube Music lẫn trình duyệt web (YouTube, Netflix trên Safari, Chrome, Arc) với tua nhanh trực tiếp.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Ngăn Kéo Notch Shelf & Thả Nhanh",
    "feat4.desc": "Biến phần khuyết tai thỏ thành nơi lưu tạm tài liệu thông minh. Kéo thả file, ảnh, đường link hoặc đoạn mã lên đỉnh màn hình để chuyển đổi nhanh giữa các app.",
    "shelf.dropText": "Thả tệp vào đây",

    "feat5.title": "Trung Tâm Màn Hình & DDC Phần Cứng",
    "feat5.desc": "Điều chỉnh độ sáng và âm lượng từng màn hình từ Display Hub hoặc phần cứng màn hình ngoài qua DDC/CI với phím F1/F2 nhận diện chuột và gộp lệnh I2C 2.2ms.",
    "bento.ddcBrightness": "Độ sáng màn hình Dell UltraSharp 4K",
    "bento.ddcVolume": "Âm lượng loa tích hợp",

    "feat6.title": "Giám Sát Phần Cứng CPU, RAM & GPU",
    "feat6.desc": "Theo dõi hiệu năng phần cứng theo thời gian thực ngay trên tai thỏ. Kiểm soát dung lượng RAM Hợp nhất, xung nhịp CPU và tải GPU mà không tốn CPU lúc chạy nền.",
    "bento.cpuCores": "8 Nhân Đang Hoạt Động",
    "bento.ramUsage": "10.3 / 16 GB Đang Dùng",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "Lịch Âm Dương & Lịch Phụ Đa Quốc Gia",
    "feat7.desc": "Thuật toán thiên văn ngoại tuyến chính xác cho Âm lịch Việt Nam (UTC+7, Hồ Ngọc Đức), Nông lịch Trung Quốc/Đài Loan (UTC+8), Lịch Hồi giáo, Do Thái, Phật lịch và Ba Tư. Nút Mặt Trăng tiện lợi xem ngày âm ngay dưới lưới tháng.",
    "feat7.monthTitle": "Tháng 9, 2026",
    "feat7.moonBadge": "Âm Lịch VN",
    "feat7.eventBadge": "27 Th9 (17/8 Âm Lịch)",
    "feat7.eventTitle": "Sự Kiện Ra Mắt NotchPulse",
    "feat7.eventTime": "19:00 - 20:30 • Đồng bộ cả ngày",

    "feat8.title": "Bảo Vệ Tuổi Thọ Pin & Giới Hạn Sạc 80%",
    "feat8.desc": "Can thiệp trực tiếp bộ điều khiển nguồn SMC của Apple Silicon. Tự động dừng sạc ở mức tối ưu 80% để chống chai pin, hỗ trợ sạc đầy 100% chỉ với 1 chạm.",

    "feat9.title": "Bộ Nhớ Tạm Thông Minh & Lưu Trữ Nhanh",
    "feat9.desc": "Khung nhìn 3 mục thoải mái, tìm kiếm tức thì và bảo vệ cuộn AppKit native. Sao chép và dán snippet, mã màu HEX, văn bản tiện lợi ngay trên notch.",

    "feat10.title": "Giao Diện 9 Ngôn Ngữ Bản Địa",
    "feat10.desc": "Hỗ trợ bản địa hóa toàn diện cho 9 ngôn ngữ: Tiếng Anh, Tiếng Việt, 繁體中文, 简体中文, 日本語, Deutsch, Français, Español, العربية với khả năng chuyển đổi tức thì.",

    "feat11.title": "Điều Khiển Quạt & Nhiệt Độ Phần Cứng Native",
    "feat11.desc": "Can thiệp trực tiếp SMC phần cứng với cơ chế tự động cấp quyền Root an toàn. Kiểm soát tốc độ quạt (Auto, Max Turbo, Silent, Tuỳ chỉnh RPM) và giám sát nhiệt độ CPU/GPU tức thì ngay từ Notch.",

    "feat12.title": "Trung Tâm Âm Thanh & Pin Thiết Bị Bluetooth",
    "feat12.desc": "Chuyển đổi thiết bị đầu ra và micro tức thì ngay trên notch. Điều chỉnh âm lượng riêng biệt cho từng ứng dụng và theo dõi phần trăm pin AirPods, tai nghe Bluetooth theo thời gian thực.",
    "bento.audioOutputs": "AirPods Pro • 92% Pin",
    "bento.audioApps": "Điều Chỉnh Âm Lượng Từng App • Spotify & Safari",
    "bento.audioTabOutput": "Đầu ra",
    "bento.audioTabInput": "Micro",

    "feat13.title": "Mở Khoá Quyền Hệ Thống & Face ID Rảnh Tay",
    "feat13.desc": "Tự động bắt lệnh quyền quản trị sudo, xác thực Keychain và hộp thoại Touch ID trên macOS. Xác thực sinh trắc học rảnh tay qua Apple Vision trên máy mà không cần gõ mật khẩu.",
    "bento.authIntercept": "Bắt Lệnh sudo Terminal & Keychain",
    "bento.authFaceID": "Xác Thực Sinh Trắc Học Apple Vision",
    "bento.authStatus": "Đã Mở Khoá Tự Động Rảnh Tay",

    "bento.fanRpm": "4.800 RPM Cực Đại",
    "bento.fanCpuTemp": "CPU 42°C • Tản Nhiệt Siêu Mát",
    "bento.fanRootAuth": "Quyền Root Tự Động An Toàn",

    "feat14.title": "Launchpad Home Cho macOS Đời Mới",
    "feat14.desc": "Mang trở lại lưới ứng dụng toàn màn hình phân trang cổ điển trên mọi phiên bản macOS. Hỗ trợ kéo chuột & vuốt 2 ngón chuyển trang, thư mục, tìm kiếm nhanh dưới tai thỏ, tự căn tỉ lệ màn hình lớn 4K/5K và chặn toàn bộ phím F4, Góc Nóng, Dock & chụm 4 ngón.",
    "bento.lpSearch": "Tìm kiếm ứng dụng & thư mục (⇧⌘L)",
    "bento.lpTabPage1": "Trang 1",
    "bento.lpTabPage2": "Trang 2",
    "bento.lpTabFolder": "Thư mục",
    "bento.lpFolderUtilities": "Công cụ Dev",
    "bento.lpBadgeScaling": "Tỉ Lệ Full Màn Hình 4K/5K",
    "bento.lpBadgeIntercept": "Chặn F4 • Hot Corner • Chụm 4 Ngón",

    "feat15.title": "HUD Phần Cứng 60Hz Siêu Mượt",
    "feat15.desc": "Thay thế hoàn toàn HUD Âm lượng, Độ sáng, Đèn nền bàn phím & Sạc MagSafe mà không bị chồng chéo hệ thống. Giữ phím tăng giảm trượt liên tục 60Hz mượt như thanh kéo, hỗ trợ vuốt trực tiếp trên tai thỏ và chế độ Inline gọn gàng.",
    "bento.hudVolumeLabel": "Âm lượng",
    "bento.hudBrightLabel": "Độ sáng",
    "bento.hudRampBadge": "Nội Suy Giữ Phím 60Hz",
    "bento.hudInlineBadge": "Inline & Kéo Thanh Trực Tiếp",

    "feat16.title": "Trình Phát Màn Hình Khóa & Trình Duyệt",
    "feat16.desc": "Hiển thị ảnh bìa, điều khiển nhạc và xem lời bài hát trực tiếp ngay trên Màn hình khóa macOS. Điều khiển đồng bộ YouTube, Netflix, Safari, Chrome, Arc, Spotify & Apple Music xuyên suốt khi mở khóa.",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "HUD Màn Hình Khóa & Lời Nhạc",

    "feat17.title": "Cài Đặt Chuẩn Apple HIG & Tìm Kiếm Sâu",
    "feat17.desc": "Thiết kế theo chuẩn Apple Human Interface Guidelines: thanh bên NavigationSplitView xuyên thấu, đồng bộ Sáng/Tối tự động, thẻ bo góc hệ thống, tìm kiếm NSSearchField tô sáng tức thì và Feature Tour hướng dẫn từng bước.",
    "bento.higSearch": "⌘ Tìm 582 mục cài đặt...",
    "bento.higRow1": "Chặn F4 & Cử Chỉ Launchpad",
    "bento.higRow2": "Feature Tour Hướng Dẫn",
    "bento.higBadge": "Chuẩn HIG Siêu Nhanh",

    // Reviews Section
    "reviews.tag": "Cộng Đồng Toàn Cầu",
    "reviews.title": "Được Yêu Thích Trên Toàn Thế Giới",
    "reviews.subtitle": "Phản hồi thực tế từ các lập trình viên, nhà thiết kế UI/UX trên khắp thế giới với các mức đánh giá phong phú.",
    "reviews.all": "Tất Cả Đánh Giá (4.8 ★)",
    "reviews.five": "5 Sao",
    "reviews.fourPointFive": "4.5 Sao",
    "reviews.four": "4 Sao",

    // Creator Section
    "creator.tag": "Gặp Gỡ Tác Giả",
    "creator.bio": "Sinh viên ITM đam mê System Design và kiến trúc hệ thống native trên macOS. Xây dựng NotchPulse từ số 0 để học hỏi, trải nghiệm tương tác người - máy và biến tai thỏ MacBook thành một không gian tiện ích thú vị.",

    // Installation Section
    "install.tag": "Sẵn Sàng Nâng Cấp Máy Mac Của Bạn?",
    "install.title": "Cài Đặt NotchPulse Ngay Hôm Nay",
    "install.subtitle": "Tương thích hoàn toàn với mọi phiên bản macOS (macOS Monterey, Ventura, Sonoma, Sequoia và mới hơn). Tối ưu hóa cho tất cả các dòng máy Mac (Apple Silicon & Intel).",
    "install.btnDmg": "Tải Trực Tiếp NotchPulse.dmg",

    // Footer
    "footer.rights": "© 2026 NotchPulse bởi Kun Nguyen (HieuKun). Bảo lưu mọi quyền.",
    "footer.releases": "Phiên Bản",
    "footer.support": "Hỗ Trợ",

    // Toast
    "toast.copied": "Đã sao chép lệnh Homebrew vào bộ nhớ tạm!",

    // Hugo / Hani Learning
    "hugo.tag": "Dự Án Bạn Bè • Học Tiếng Trung Hani",
    "hugo.sub": "Website học tiếng Trung hiện đại do Đỗ Mạnh Hùng (Hugo) sáng lập",
    "hugo.btn": "Đăng ký nhận 2000 xu Hani"
  },

  de: {
    // Navigation
    "nav.skip": "Zum Hauptinhalt springen",
    "nav.features": "Funktionen",
    "nav.demo": "Live-Demo",
    "nav.reviews": "Bewertungen",
    "nav.creator": "Entwickler",
    "nav.download": "Download",
    "nav.get": "App laden (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} Veröffentlicht",
    "hero.title": "MacBook Notch, neu definiert.",
    "hero.titleMain": "MacBook Notch,",
    "hero.titleAccent": "neu definiert.",
    "hero.subtitle": "Verwandle die MacBook-Kamerakerbe in eine flüssige 120Hz ProMotion Dynamic Island – jetzt mit klassischem Launchpad Home, flüssigen 60Hz HUDs, Face ID, Sperrbildschirm-Player und Browser-Mediensteuerung.",
    "hero.downloadBtn": "NotchPulse.dmg herunterladen ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Bestätigt",
    "chip.faceidSub": "On-Device Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "Klassisches Raster • F4 & Pinch",
    "chip.hudTitle": "Flüssige 60Hz HUDs",
    "chip.hudSub": "Lautstärke, Helligkeit & Tastenlicht",
    "chip.settingsTitle": "Native HIG-Einstellungen",
    "chip.settingsSub": "Live-Suche & Feature-Tour",
    "chip.ddcTitle": "DDC Display-Steuerung",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Aktiv",
    "chip.batterySub": "Intelligenter 80% Ladeschutz",
    "chip.shelfTitle": "Notch-Ablage Bereit",
    "chip.shelfSub": "Drag & Drop + AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU-Last im Leerlauf",
    "chip.lyricsTitle": "Browser & Musik-Sync",
    "chip.lyricsSub": "Spotify, Musik, YouTube & Web",
    "chip.statsTitle": "Systemmonitor",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "Zwischenablage",
    "chip.clipboardSub": "50 Einträge • ⌘⌥V",
    "chip.lunarTitle": "Mond- & Regionalkalender",
    "chip.lunarSub": "Mondkalender • Hijri • Hebräisch",
    "chip.islandTitle": "Dynamic Island Modus",
    "chip.islandSub": "Pixelgenaue Bezier-Kurve",
    "chip.lockscreenTitle": "Sperrbildschirm-Player",
    "chip.lockscreenSub": "Live-Steuerung & Songtexte",
    "chip.displayTitle": "Multi-Display-Hub",
    "chip.displaySub": "Nahtlose Bildschirm-Sync",

    // Demo Controls
    "demo.modeNotch": "MacBook Notch",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Songtexte",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "Ablage",
    "demo.hint": "Klicke oder bewege die Maus über die Notch oben, um die 120Hz-Erweiterung zu erleben!",
    "notch.idle": "NotchPulse Aktiv",
    "notch.faceIdScanned": "Face ID Bestätigt",
    "notch.faceIdPrompt": "Mac nahtlos über Frontkamera entsperrt",
    "notch.batteryPrompt": "Vollständig in 18 Minuten • Akkuzustand: 100%",
    "notch.shelfItems": "Ablage: 3 Elemente",
    "notch.shelfPrompt": "Dateien in die Notch ziehen zum Zwischenspeichern",

    // Bento Features Section
    "features.tag": "Entwickelt für macOS",
    "features.title": "Volle Kontrolle über Ihre MacBook Notch",
    "features.subtitle": "Nativ in Swift entwickelt mit 0% CPU-Last im Leerlauf. Erlebe Launchpad Home, flüssige 120Hz ProMotion & 60Hz HUDs, Face ID, Sperrbildschirm-Player und smarte Werkzeuge.",
    
    "feat1.title": "Biometrische Face ID Erkennung",
    "feat1.desc": "Bringt iOS-Gesichtserkennung auf deinen Mac. Kontinuierliche Anwesenheitserkennung und sicheres Entsperren mit Apple Vision direkt auf dem Gerät.",
    "bento.faceidVerified": "Neural Face Mesh Aktiv",
    "bento.faceidSub": "512D Vektor-Embedding • On-Device Apple Vision",
    "bento.faceidHandshake": "Sperrbildschirm-zu-Desktop Handshake ohne Verzögerung",

    "feat2.title": "120Hz ProMotion Dual-Modus",
    "feat2.desc": "Wechselt flüssig zwischen nativer MacBook Notch und zentrierter Dynamic Island auf externen Bildschirmen.",
    "bento.springPhysics": "Apple Federphysik (Reaktion: 0.38s)",

    "feat3.title": "Live-Songtexte & Browser-Medien",
    "feat3.desc": "Wortgenaue Songtexte und Mediensteuerung für Spotify, Apple Music, YouTube Music und Browser (YouTube, Netflix in Safari, Chrome & Arc) direkt in der Notch.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf & Schnelles Ablegen",
    "feat4.desc": "Dateien, Links oder Bildschirmfotos direkt in die Notch ziehen, um sie zwischen Schreibtischen und Apps bereitzuhalten.",
    "shelf.dropText": "Dateien hier ablegen",

    "feat5.title": "Multi-Display-Hub & DDC-Steuerung",
    "feat5.desc": "Steuere Helligkeit und Lautstärke interner und externer Monitore über den Display-Hub oder DDC/CI mit cursor-gesteuerten F1/F2-Tasten und 2,2ms Write-Coalescing.",
    "bento.ddcBrightness": "Dell UltraSharp 4K Helligkeit",
    "bento.ddcVolume": "Integrierte Lautstärke",

    "feat6.title": "Echtzeit CPU, RAM & GPU Monitor",
    "feat6.desc": "Hardware-Telemetrie direkt in der Notch. Apple Silicon Speicherdruck, CPU-Cluster und GPU-Last mit 0% Leerlauf-Overhead überwachen.",
    "bento.cpuCores": "8 Kerne Aktiv",
    "bento.ramUsage": "10.3 / 16 GB Aktiv",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "Regionaler Mond- & Mehrländer-Kalender",
    "feat7.desc": "Astronomische Offline-Berechnung für vietnamesischen Mondkalender (UTC+7), chinesischen Nongli (UTC+8), Hijri, Hebräisch, Buddhistisch und Persisch.",
    "feat7.monthTitle": "September 2026",
    "feat7.moonBadge": "Mondkalender",
    "feat7.eventBadge": "27. Sep. (17/8 Mondkalender)",
    "feat7.eventTitle": "NotchPulse Produkt-Launch",
    "feat7.eventTime": "19:00 - 20:30 • Ganztägige Synchr.",

    "feat8.title": "Intelligenter 80% Akkuschutz",
    "feat8.desc": "Direkte Apple Silicon SMC-Steuerung. Begrenzt das Laden auf schonende 80% für maximale Lebensdauer mit 1-Klick 100% Schnellladung.",

    "feat9.title": "Intelligente Zwischenablage & Snippets",
    "feat9.desc": "Komfortabler 3-Elemente-Viewport, Sofortsuche und nativer AppKit-Scrollschutz. Snippets, Farbcodes und Text direkt aus der Notch kopieren.",

    "feat10.title": "Native Lokalisierung in 9 Sprachen",
    "feat10.desc": "Vollständige Benutzeroberfläche in Englisch, Vietnamesisch, Chinesisch (Trad./Simp.), Japanisch, Deutsch, Französisch, Spanisch und Arabisch.",

    "feat11.title": "Native SMC-Lüfter- & Temperatursteuerung",
    "feat11.desc": "Direkter SMC-Hardwaretreiber mit automatischer Root-Autorisierung. Lüfterstufen (Auto, Max Blast, Silent, Custom RPM) und CPU/GPU-Temperatur direkt in der Notch steuern.",

    "feat12.title": "Interaktiver Audio-Hub & Bluetooth-Batterie",
    "feat12.desc": "Ausgabegeräte und Mikrofone direkt in der Notch umschalten. Individuelle Lautstärkeregler pro App verwalten und AirPods- & Bluetooth-Akkustände in Echtzeit überwachen.",
    "bento.audioOutputs": "AirPods Pro • 92% Batterie",
    "bento.audioApps": "App-Lautstärkemixer • Spotify & Safari",
    "bento.audioTabOutput": "Ausgabe",
    "bento.audioTabInput": "Eingabe",

    "feat13.title": "macOS-Systemauthentifizierung & Hands-Free Face ID",
    "feat13.desc": "Fängt sudo-Eingabeaufforderungen, Schlüsselbundabfragen und Touch ID-Dialoge unter macOS ab. Nahtlose Authentifizierung über On-Device Apple Vision ohne Passworteingabe.",
    "bento.authIntercept": "Terminal-sudo & Schlüsselbund-Abfangung",
    "bento.authFaceID": "Apple Vision Biometrische Verifizierung",
    "bento.authStatus": "Hands-Free Authentifiziert",

    "bento.fanRpm": "4.800 U/min Turbo",
    "bento.fanCpuTemp": "CPU 42°C • Kühl & Leise",
    "bento.fanRootAuth": "Root-Daemon Aktiv",

    "feat14.title": "Launchpad Home für modernes macOS",
    "feat14.desc": "Bringt das klassische Vollbild-App-Raster auf jedes macOS zurück. Mit Mausziehen & Trackpad-Wischen, Ordnern, Sofortsuche unter der Notch, proportionaler 4K/5K-Skalierung und kompletter Blockierung von F4-Taste, Aktiven Ecken, Dock & Pinch-Geste.",
    "bento.lpSearch": "Apps & Ordner suchen (⇧⌘L)",
    "bento.lpTabPage1": "Seite 1",
    "bento.lpTabPage2": "Seite 2",
    "bento.lpTabFolder": "Ordner",
    "bento.lpFolderUtilities": "Entwicklertools",
    "bento.lpBadgeScaling": "4K/5K Vollbild-Skalierung",
    "bento.lpBadgeIntercept": "F4 • Aktive Ecke • 4-Finger-Pinch",

    "feat15.title": "Butterweiche 60Hz Hardware-HUDs",
    "feat15.desc": "Ersetzt System-HUDs für Lautstärke, Helligkeit, Tastaturbeleuchtung und MagSafe ohne Überlappung. Kontinuierliche 60Hz-Tastenrampe beim Halten, direktes Ziehen in der Notch sowie Inline- & Open-Modus.",
    "bento.hudVolumeLabel": "Lautstärke",
    "bento.hudBrightLabel": "Helligkeit",
    "bento.hudRampBadge": "60Hz Halte-Interpolation",
    "bento.hudInlineBadge": "Inline & Direktes Ziehen",

    "feat16.title": "Sperrbildschirm-Player & Browser-Steuerung",
    "feat16.desc": "Zeigt Albumcover, Wiedergabesteuerung und Live-Songtexte direkt auf dem macOS-Sperrbildschirm. Steuert YouTube, Netflix, Safari, Chrome, Arc, Spotify & Apple Music mit nahtlosem Übergang zum Desktop.",
    "bento.lsSourceBadge": "Safari • YouTube • Musik",
    "bento.lsLyricsStatus": "Sperrbildschirm-HUD & Live-Texte",

    "feat17.title": "Native macOS HIG-Einstellungen & Suche",
    "feat17.desc": "Gestaltet nach Apple HIG: transluzente NavigationSplitView-Seitenleiste, automatisches Hell/Dunkel-Design, gruppierte Karten, Live-Suche mit Spotlight-Fokus und interaktive Feature-Tour.",
    "bento.higSearch": "⌘ 582 Einstellungen durchsuchen...",
    "bento.higRow1": "F4 & Gesten abfangen",
    "bento.higRow2": "Feature-Tour Spotlight",
    "bento.higBadge": "Natives macOS HIG",

    // Reviews Section
    "reviews.tag": "Globale Community",
    "reviews.title": "Geschätzt von Entwicklern weltweit",
    "reviews.subtitle": "Echtes Feedback von macOS-Entwicklern, Designern und Power-Usern rund um den Globus.",
    "reviews.all": "Alle Bewertungen (4.8 ★)",
    "reviews.five": "5 Sterne",
    "reviews.fourPointFive": "4.5 Sterne",
    "reviews.four": "4 Sterne",
    "reviews.threePointFive": "3.5 Sterne",

    // Creator Section
    "creator.tag": "Über den Entwickler",
    "creator.bio": "ITM-Student mit Leidenschaft für Systemarchitektur und native macOS-Entwicklung. Hat NotchPulse von Grund auf gebaut, um Mensch-Computer-Interaktion zu erforschen und die Notch nützlich zu machen.",

    // Installation Section
    "install.tag": "Bereit für das nächste Level?",
    "install.title": "Hol dir NotchPulse noch heute",
    "install.subtitle": "Kompatibel mit allen macOS-Versionen (Monterey, Ventura, Sonoma, Sequoia & neuer). Optimiert für alle Mac-Geräte (Apple Silicon & Intel).",
    "install.btnDmg": "NotchPulse.dmg herunterladen (Direkt)",

    // Footer
    "footer.rights": "© 2026 NotchPulse von Kun Nguyen (HieuKun). Alle Rechte vorbehalten.",
    "footer.releases": "Versionen",
    "footer.support": "Support",

    // Toast
    "toast.copied": "Homebrew-Befehl in Zwischenablage kopiert!",

    // Hugo / Hani Learning
    "hugo.tag": "Partner-Projekt • Hani Chinesisch Lernen",
    "hugo.sub": "Moderne Plattform zum Chinesischlernen, gegründet von Do Manh Hung (Hugo)",
    "hugo.btn": "Registrieren & 2.000 Hani-Münzen erhalten"
  },

  ja: {
    // Navigation
    "nav.skip": "メインコンテンツへスキップ",
    "nav.features": "機能紹介",
    "nav.demo": "ライブデモ",
    "nav.reviews": "レビュー",
    "nav.creator": "開発者",
    "nav.download": "ダウンロード",
    "nav.get": "アプリを入手 (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} リリース",
    "hero.title": "MacBookのノッチを、再定義。",
    "hero.titleMain": "MacBookのノッチを、",
    "hero.titleAccent": "再定義。",
    "hero.subtitle": "MacBookのノッチを滑らかな120Hz ProMotion Dynamic Islandへ進化。最新のmacOS向けLaunchpad Home、60HzスムーズHUD、Face ID、ロック画面プレイヤー、ブラウザメディア操作まで完全統合。",
    "hero.downloadBtn": "NotchPulse.dmg をダウンロード ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 認証完了",
    "chip.faceidSub": "デバイス内 Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "ページグリッド • F4 & ピンチ対応",
    "chip.hudTitle": "滑らか 60Hz HUD",
    "chip.hudSub": "音量・輝度・キーボードライト",
    "chip.settingsTitle": "ネイティブ HIG 設定",
    "chip.settingsSub": "リアルタイム検索 & ツアー",
    "chip.ddcTitle": "DDC ディスプレイ制御",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 稼働中",
    "chip.batterySub": "スマート80%充電保護",
    "chip.shelfTitle": "ノッチシェルフ対応",
    "chip.shelfSub": "ドラッグ＆ドロップ + AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "アイドル時CPU負荷 0%",
    "chip.lyricsTitle": "音楽 & ブラウザ同期",
    "chip.lyricsSub": "Spotify・Music・YouTube・Web",
    "chip.statsTitle": "システムモニター",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "クリップボード履歴",
    "chip.clipboardSub": "50件保持 • ⌘⌥V",
    "chip.lunarTitle": "旧暦・地域別カレンダー",
    "chip.lunarSub": "旧暦 • ヒジュラ暦 • ユダヤ暦",
    "chip.islandTitle": "ダイナミックアイランド",
    "chip.islandSub": "高精度ベジェ曲線",
    "chip.lockscreenTitle": "ロック画面プレイヤー",
    "chip.lockscreenSub": "操作パネル & 同期歌詞",
    "chip.displayTitle": "マルチディスプレイ同期",
    "chip.displaySub": "スマート単一ノッチ制御",

    // Demo Controls
    "demo.modeNotch": "ノッチモード",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "同期歌詞",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "ノッチシェルフ",
    "demo.hint": "ノッチをクリックまたはホバーして、120Hzの滑らかな展開を体験！",
    "notch.idle": "NotchPulse 稼働中",
    "notch.faceIdScanned": "Face ID 認証完了",
    "notch.faceIdPrompt": "フロントカメラ経由でMacをスムーズに解除",
    "notch.batteryPrompt": "満充電まで18分 • バッテリー状態: 100%",
    "notch.shelfItems": "シェルフ: 3項目",
    "notch.shelfPrompt": "ファイルをノッチにドラッグして一時保存",

    // Bento Features Section
    "features.tag": "macOS 専用設計",
    "features.title": "MacBook ノッチを究極に進化",
    "features.subtitle": "Swiftネイティブ開発、アイドル時CPU消費0%。Launchpad Home、60Hz滑らかHUD、Face ID生体認証、ロック画面ライブプレイヤーなど先進機能を搭載。",
    
    "feat1.title": "生体認証 Face ID 顔認識",
    "feat1.desc": "iPhone品質の顔認識をMacへ。Apple Visionによるデバイス内処理で、プライバシーを守りながら安全にロック解除。",
    "bento.faceidVerified": "Neural Face Mesh 稼働中",
    "bento.faceidSub": "512D ベクトル埋め込み • デバイス内 Apple Vision",
    "bento.faceidHandshake": "ロック画面からデスクトップへ遅延ゼロの連携",

    "feat2.title": "120Hz ProMotion デュアルモード",
    "feat2.desc": "MacBookの内蔵ノッチと外部ディスプレイ上のDynamic Islandをシームレスに切り替え。",
    "bento.springPhysics": "Apple スプリング物理演算 (応答: 0.38s)",

    "feat3.title": "同期歌詞 & ユニバーサルメディア対応",
    "feat3.desc": "Spotify、Apple Music、YouTube Musicに加えSafari・Chrome・Arc上のYouTubeやNetflixをノッチで直接シーク操作＆リアルタイム歌詞表示。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "ノッチシェルフ & クイックドロップ",
    "feat4.desc": "ファイル、リンク、スクリーンショットをノッチに直接ドラッグして、アプリやワークスペース間で一時保存。",
    "shelf.dropText": "ここにファイルをドロップ",

    "feat5.title": "マルチディスプレイハブ & DDC制御",
    "feat5.desc": "内蔵・外部モニターの輝度や音量を統合ハブまたはDDC/CIで直接制御。カーソル追従F1/F2キーと2.2ms高速統合書き込みに対応。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 輝度",
    "bento.ddcVolume": "内蔵オーディオ音量",

    "feat6.title": "CPU・RAM・GPU リアルタイム監視",
    "feat6.desc": "Apple Siliconのメモリプレッシャー、CPUコア稼働率、GPU負荷をノッチ上で常時把握。",
    "bento.cpuCores": "8コア 稼働中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "旧暦・地域別マルチカレンダー",
    "feat7.desc": "ベトナム旧暦（UTC+7）、中国農暦（UTC+8）、イスラム暦、ユダヤ暦、仏暦、ペルシア暦の高精度オフライン計算に対応。月表示ボタンで旧暦日付を表示。",
    "feat7.monthTitle": "2026年9月",
    "feat7.moonBadge": "旧暦表示",
    "feat7.eventBadge": "9月27日 (旧暦 17/8)",
    "feat7.eventTitle": "NotchPulse 製品発表会",
    "feat7.eventTime": "19:00 - 20:30 • 終日同期",

    "feat8.title": "スマート80%バッテリー保護",
    "feat8.desc": "Apple Silicon SMC直接制御。バッテリー劣化を防ぐ80%充電リミットと、1タップでの100%フル充電切り替えに対応。",

    "feat9.title": "スマートクリップボード履歴",
    "feat9.desc": "快適な3項目表示、高速検索、AppKitネイティブスクロール保護。コード、カラーコード、テキストをノッチから瞬時にコピー＆ペースト。",

    "feat10.title": "9言語ネイティブローカライズ",
    "feat10.desc": "英語、ベトナム語、繁体字、簡体字、日本語、ドイツ語、フランス語、スペイン語、アラビア語のリアルタイム言語切り替えに対応。",

    "feat11.title": "ネイティブ SMC ファン＆温度管理",
    "feat11.desc": "自動Root認証を備えたSMC直接ハードウェア制御。ノッチから直接ファン速度（Auto、Max、静音、カスタムRPM）とCPU/GPU温度をリアルタイム管理。",

    "feat12.title": "オーディオハブ＆Bluetoothバッテリー管理",
    "feat12.desc": "ノッチ内で直接出力先やマイクを瞬時に切り替え。アプリごとの音量スライダーの個別調整や、AirPods・Bluetoothヘッドフォンのバッテリー残量をリアルタイムで確認可能。",
    "bento.audioOutputs": "AirPods Pro • バッテリー 92%",
    "bento.audioApps": "アプリ別音量ミキサー • Spotify & Safari",
    "bento.audioTabOutput": "出力",
    "bento.audioTabInput": "入力",

    "feat13.title": "macOSシステム認証＆ハンズフリーFace ID",
    "feat13.desc": "macOSの管理者sudoプロンプト、キーチェーン認証、Touch IDダイアログを自動インターセプト。パスワード入力不要でオンデバイスApple Visionによる生体認証を実現。",
    "bento.authIntercept": "Terminal sudo & キーチェーン横断インターセプト",
    "bento.authFaceID": "Apple Vision 高精度生体認識",
    "bento.authStatus": "ハンズフリー認証完了",

    "bento.fanRpm": "4,800 RPM ターボ",
    "bento.fanCpuTemp": "CPU 42°C • 低温静音",
    "bento.fanRootAuth": "Root認証自動管理",

    "feat14.title": "最新macOS向け Launchpad Home",
    "feat14.desc": "クラシックな全画面ページ型アプリグリッドをあらゆるmacOSで復活。マウスドラッグ＆2本指スワイプ、フォルダ管理、ノッチ下検索、4K/5K外部画面の比率スケーリング、F4キー・ホットコーナー・ピンチ操作の完全インターセプトに対応。",
    "bento.lpSearch": "アプリ・フォルダを検索 (⇧⌘L)",
    "bento.lpTabPage1": "ページ 1",
    "bento.lpTabPage2": "ページ 2",
    "bento.lpTabFolder": "フォルダ",
    "bento.lpFolderUtilities": "開発ツール",
    "bento.lpBadgeScaling": "4K/5K フルスクリーン最適化",
    "bento.lpBadgeIntercept": "F4・ホットコーナー・4本指ピンチ",

    "feat15.title": "超滑らか 60Hz ハードウェア HUD",
    "feat15.desc": "音量・画面輝度・キーボードライト・MagSafe充電HUDをシステム重複なしで置換。長押し時の60Hz連続補間、ノッチバーの直接ドラッグ調整、インライン/オープン切替を実現。",
    "bento.hudVolumeLabel": "音量",
    "bento.hudBrightLabel": "輝度",
    "bento.hudRampBadge": "60Hz 連続長押し補間",
    "bento.hudInlineBadge": "インライン＆ドラッグ調整",

    "feat16.title": "ロック画面プレイヤー & ブラウザ同期",
    "feat16.desc": "macOSロック画面上にアートワーク・再生コントロール・オンデマンド歌詞を表示。YouTube、Netflix、Safari、Chrome、Arc、Spotify、Apple Musicをシームレスに連携操作。",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "ロック画面 HUD & 歌詞表示",

    "feat17.title": "macOS HIG 準拠設定 & インスタント検索",
    "feat17.desc": "Apple HIG準拠の半透明NavigationSplitView、ライト/ダーク自動追従、グループ化カード、NSSearchFieldによるスポットライト検索、対話型Feature Tourを搭載。",
    "bento.higSearch": "⌘ 582項目を検索...",
    "bento.higRow1": "F4 & ジェスチャー制御",
    "bento.higRow2": "Feature Tour スポットライト",
    "bento.higBadge": "ネイティブ HIG",

    // Reviews Section
    "reviews.tag": "グローバルコミュニティ",
    "reviews.title": "世界中の開発者から高評価",
    "reviews.subtitle": "世界各地のMacエンジニアやデザイナーからのリアルなフィードバック。",
    "reviews.all": "すべてのレビュー (4.8 ★)",
    "reviews.five": "5つ星",
    "reviews.fourPointFive": "4.5つ星",
    "reviews.four": "4つ星",
    "reviews.threePointFive": "3.5つ星",

    // Creator Section
    "creator.tag": "開発者について",
    "creator.bio": "システム設計とmacOSネイティブ開発に情熱を注ぐITMの学生。人とコンピュータの相互作用を探求し、MacBookのノッチを実用的で心地よい空間にするためNotchPulseを一から開発。",

    // Installation Section
    "install.tag": "あなたのMacを進化させる",
    "install.title": "NotchPulse を今すぐ体験",
    "install.subtitle": "すべてのmacOSバージョン（Monterey、Ventura、Sonoma、Sequoia 以降）に対応。Apple Silicon および Intel 搭載の全Macに最適化。",
    "install.btnDmg": "NotchPulse.dmg を直接ダウンロード",

    // Footer
    "footer.rights": "© 2026 NotchPulse by Kun Nguyen (HieuKun). 無断転載を禁じます。",
    "footer.releases": "リリース",
    "footer.support": "サポート",

    // Toast
    "toast.copied": "Homebrewコマンドをクリップボードにコピーしました！",

    // Hugo / Hani Learning
    "hugo.tag": "おすすめプロジェクト • Hani 中国語学習",
    "hugo.sub": "Do Manh Hung (Hugo) が創設した現代的な中国語学習プラットフォーム",
    "hugo.btn": "登録して2,000 Haniコインを獲得"
  },

  "zh-TW": {
    // Navigation
    "nav.skip": "跳至主要內容",
    "nav.features": "特色功能",
    "nav.demo": "即時演示",
    "nav.reviews": "用戶評價",
    "nav.creator": "開發者",
    "nav.download": "下載",
    "nav.get": "取得應用 (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} 正式發佈",
    "hero.title": "MacBook 瀏海，重塑想像。",
    "hero.titleMain": "MacBook 瀏海，",
    "hero.titleAccent": "重塑想像。",
    "hero.subtitle": "將 MacBook 鏡頭瀏海蛻變為流暢的 120Hz ProMotion 靈動島。整合新版 macOS Launchpad Home、60Hz 絲滑硬體 HUD、Face ID 辨識、鎖定畫面播放器與跨瀏覽器音樂控制。",
    "hero.downloadBtn": "下載 NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 認證成功",
    "chip.faceidSub": "本機端 Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "經典分頁網格 • F4 與雙指手勢",
    "chip.hudTitle": "絲滑 60Hz HUD",
    "chip.hudSub": "音量、亮度與鍵盤背光",
    "chip.settingsTitle": "原生 HIG 設定介面",
    "chip.settingsSub": "即時搜尋與功能導覽",
    "chip.ddcTitle": "DDC 螢幕硬體控制",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 充能中",
    "chip.batterySub": "智慧 80% 充電保護",
    "chip.shelfTitle": "瀏海暫存區已就緒",
    "chip.shelfSub": "拖放暫存 + AirDrop 分享",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "待機時 0% CPU 佔用",
    "chip.lyricsTitle": "音樂與瀏覽器同步",
    "chip.lyricsSub": "Spotify、Music、YouTube 與網頁",
    "chip.statsTitle": "系統監控 (Stats)",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "剪貼簿紀錄",
    "chip.clipboardSub": "50 筆紀錄 • 快速 ⌘⌥V",
    "chip.lunarTitle": "農曆與多國曆法",
    "chip.lunarSub": "農曆 • 回曆 • 希伯來曆",
    "chip.islandTitle": "動態島靈動模式",
    "chip.islandSub": "像素級貝茲曲線",
    "chip.lockscreenTitle": "鎖定畫面播放器",
    "chip.lockscreenSub": "即時播放控制與動態歌詞",
    "chip.displayTitle": "多螢幕協同中樞",
    "chip.displaySub": "智慧單一瀏海切換",

    // Demo Controls
    "demo.modeNotch": "MacBook 瀏海",
    "demo.modeIsland": "靈動島模式",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "動態歌詞",
    "demo.pillBattery": "98W 充能",
    "demo.pillShelf": "暫存懸崖",
    "demo.hint": "點擊或將滑鼠懸停於上方瀏海，感受 120Hz 的絲滑展開動效！",
    "notch.idle": "NotchPulse 運作中",
    "notch.faceIdScanned": "Face ID 認證成功",
    "notch.faceIdPrompt": "透過前置相機順暢解鎖 Mac",
    "notch.batteryPrompt": "18 分鐘後充滿 • 電池健康度: 100%",
    "notch.shelfItems": "暫存區: 3 個檔案",
    "notch.shelfPrompt": "將檔案拖入瀏海以在跨應用間暫存",

    // Bento Features Section
    "features.tag": "為 macOS 精密打造",
    "features.title": "全面釋放 MacBook 瀏海潛能",
    "features.subtitle": "以 Swift 原生開發，待機 0% CPU 負荷。集結 Launchpad Home、60Hz 絲滑硬體 HUD、Face ID、鎖定畫面播放器與智慧桌面工具。",
    
    "feat1.title": "生物特徵 Face ID 臉部辨識",
    "feat1.desc": "將 iOS 等級的臉部辨識帶入 Mac。持續感應使用者在位狀態，並透過 Apple Vision 於本機端安全完成辨識與解鎖。",
    "bento.faceidVerified": "類神經網格 Face Mesh 運算中",
    "bento.faceidSub": "512D 向量嵌入 • 本機端 Apple Vision",
    "bento.faceidHandshake": "鎖定畫面至桌面零延遲即時切換",

    "feat2.title": "120Hz ProMotion 雙形態模式",
    "feat2.desc": "在 MacBook 內建瀏海與外接螢幕置中靈動島之間自然變換形態。",
    "bento.springPhysics": "Apple 彈簧物理引擎 (響應: 0.38s)",

    "feat3.title": "同步歌詞與跨瀏覽器媒體控制",
    "feat3.desc": "逐字同步顯示 Spotify、Apple Music、YouTube Music 及 Safari / Chrome / Arc 上的 YouTube、Netflix 播放控制，支援直接拖曳進度條與高解析封面。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "瀏海暫存區 Notch Shelf",
    "feat4.desc": "將檔案、截圖或連結拖曳至螢幕邊緣暫存，輕鬆穿梭跨桌面與各項工作流程。",
    "shelf.dropText": "將檔案拖曳至此",

    "feat5.title": "多螢幕中樞與 DDC 硬體控制",
    "feat5.desc": "透過 Display Hub 或 DDC/CI 統一調整內建與外接螢幕硬體亮度與音量，支援游標感應 F1/F2 鍵位與 2.2ms 極速寫入。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 亮度",
    "bento.ddcVolume": "內建喇叭音量",

    "feat6.title": "即時 CPU、RAM 與 GPU 系統監控",
    "feat6.desc": "於瀏海即時掌握硬體資訊：Apple Silicon 統一記憶體壓力、CPU 核心頻率與 GPU 負載，零待機損耗。",
    "bento.cpuCores": "8 核心運作中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "農曆與多國曆法計算引擎",
    "feat7.desc": "精準天文離線運算：支援越南農曆 (UTC+7)、台港中農曆 (UTC+8)、伊斯蘭曆、希伯來曆、佛曆與波斯曆。月相按鈕一鍵展開農曆初一十五標記。",
    "feat7.monthTitle": "2026年9月",
    "feat7.moonBadge": "農曆標記",
    "feat7.eventBadge": "9月27日 (農曆 17/8)",
    "feat7.eventTitle": "NotchPulse 產品發布會",
    "feat7.eventTime": "19:00 - 20:30 • 全天同步",

    "feat8.title": "智慧型 80% 電池健康保護",
    "feat8.desc": "直接控制 Apple Silicon SMC 電源管理，將充電限制在 80% 最佳區間以延長電池壽命，出門前可一鍵充至 100%。",

    "feat9.title": "智慧剪貼簿管理與暫存",
    "feat9.desc": "舒適 3 項目直覺視窗、毫秒級即時搜尋與 AppKit 原生捲動保護。在瀏海中隨選隨貼程式碼、HEX 色碼與格式化文字。",

    "feat10.title": "9 種語系原生多國語言",
    "feat10.desc": "完整支援繁體中文、簡體中文、英文、越南文、日文、德文、法文、西班牙文與阿拉伯文，切換即時生效。",

    "feat11.title": "原生 SMC 風扇與硬體溫度控制",
    "feat11.desc": "直接介入 SMC 硬體並支援自動 Root 權限調用。直接於瀏海監控 CPU/GPU 溫度，並自由切換風扇轉速（自動、全速、靜音、自訂 RPM）。",

    "feat12.title": "互動音訊控制中心與藍牙電量管理",
    "feat12.desc": "直接在瀏海區域即時切換音訊輸出與麥克風。支援各應用程式獨立音量調節，並即時監控 AirPods 與藍牙耳機電量。",
    "bento.audioOutputs": "AirPods Pro • 剩餘電量 92%",
    "bento.audioApps": "個別應用程式音量混音 • Spotify & Safari",
    "bento.audioTabOutput": "輸出",
    "bento.audioTabInput": "輸入",

    "feat13.title": "macOS 系統權限與免動手 Face ID 認證",
    "feat13.desc": "自動攔截 macOS 管理者 sudo 提權、鑰匙圈認證與 Touch ID 提示。透過本機 Apple Vision 進行免動手臉部辨識，無須手動輸入密碼。",
    "bento.authIntercept": "終端機 sudo 與鑰匙圈安全攔截",
    "bento.authFaceID": "Apple Vision 本地神經網路驗證",
    "bento.authStatus": "免動手無感極速解鎖",

    "bento.fanRpm": "4,800 RPM 渦輪全速",
    "bento.fanCpuTemp": "CPU 42°C • 涼爽靜音",
    "bento.fanRootAuth": "Root 守護程序自動啟用",

    "feat14.title": "新版 macOS 專用 Launchpad Home",
    "feat14.desc": "在所有 macOS 版本重現經典全螢幕分頁啟動台。支援滑鼠拖曳與雙指滑動翻頁、資料夾歸納、瀏海下方即時搜尋、4K/5K 外接螢幕滿版比例縮放，並全面攔截 F4 鍵、熱點角落、Dock 與四指捏合。",
    "bento.lpSearch": "搜尋 App 與資料夾 (⇧⌘L)",
    "bento.lpTabPage1": "第 1 頁",
    "bento.lpTabPage2": "第 2 頁",
    "bento.lpTabFolder": "資料夾",
    "bento.lpFolderUtilities": "開發工具",
    "bento.lpBadgeScaling": "4K/5K 滿版比例縮放",
    "bento.lpBadgeIntercept": "F4 • 熱點角落 • 四指捏合",

    "feat15.title": "超絲滑 60Hz 硬體 HUD 指示條",
    "feat15.desc": "無重疊取代系統音量、螢幕亮度、鍵盤背光與 MagSafe 充電 HUD。長按按鍵時具備 60Hz 連續線性補間，支援在瀏海內直接拖曳調整以及精簡 Inline / 展開樣式。",
    "bento.hudVolumeLabel": "音量",
    "bento.hudBrightLabel": "亮度",
    "bento.hudRampBadge": "60Hz 長按連續補間",
    "bento.hudInlineBadge": "Inline 與直接拖曳",

    "feat16.title": "鎖定畫面播放器與跨瀏覽器同步",
    "feat16.desc": "直接在 macOS 鎖定畫面顯示專輯封面、播放控制與隨選同步歌詞。流暢操控 YouTube、Netflix、Safari、Chrome、Arc、Spotify 與 Apple Music，解鎖無縫銜接。",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "鎖定畫面 HUD 與動態歌詞",

    "feat17.title": "原生 macOS HIG 設定與深度搜尋",
    "feat17.desc": "遵循 Apple Human Interface Guidelines：透明 NavigationSplitView 側邊欄毛玻璃、自動跟隨深淺色模式、群組圓角卡片、NSSearchField 即時焦點搜尋與互動式功能導覽。",
    "bento.higSearch": "⌘ 搜尋 582 項設定...",
    "bento.higRow1": "攔截 F4 與觸控板手勢",
    "bento.higRow2": "功能導覽聚焦模式",
    "bento.higBadge": "零延遲 HIG",

    // Reviews Section
    "reviews.tag": "全球開發者社群",
    "reviews.title": "備受全球工程師與設計師喜愛",
    "reviews.subtitle": "來自全球各地專業 Mac 使用者的真實回饋與評價。",
    "reviews.all": "所有評價 (4.8 ★)",
    "reviews.five": "5 星好評",
    "reviews.fourPointFive": "4.5 星",
    "reviews.four": "4 星",
    "reviews.threePointFive": "3.5 星",

    // Creator Section
    "creator.tag": "認識開發者",
    "creator.bio": "熱衷於系統設計與 macOS 原生架構的 ITM 學生。從零開始打造 NotchPulse，探索人機互動可能性，讓 MacBook 瀏海變得兼具美感與實用。",

    // Installation Section
    "install.tag": "準備好升級您的 Mac 體驗了嗎？",
    "install.title": "立即獲取 NotchPulse",
    "install.subtitle": "相容所有 macOS 版本（Monterey、Ventura、Sonoma、Sequoia 及更新系統）。針對 Apple Silicon 與 Intel 全系列 Mac 深度優化。",
    "install.btnDmg": "直接下載 NotchPulse.dmg",

    // Footer
    "footer.rights": "© 2026 NotchPulse 由 Kun Nguyen (HieuKun) 打造。版權所有。",
    "footer.releases": "發布版本",
    "footer.support": "技術支援",

    // Toast
    "toast.copied": "已將 Homebrew 指令複製至剪貼簿！",

    // Hugo / Hani Learning
    "hugo.tag": "好友精選專案 • Hani 華語學習平台",
    "hugo.sub": "由杜孟雄 (Hugo) 創立的現代化華語學習平台",
    "hugo.btn": "註冊領取 2,000 Hani 學習幣"
  },

  "zh-CN": {
    // Navigation
    "nav.skip": "跳转到主要内容",
    "nav.features": "核心功能",
    "nav.demo": "在线演示",
    "nav.reviews": "用户评价",
    "nav.creator": "开发者",
    "nav.download": "下载",
    "nav.get": "获取应用 (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} 正式发布",
    "hero.title": "MacBook 刘海，重塑想象。",
    "hero.titleMain": "MacBook 刘海，",
    "hero.titleAccent": "重塑想象。",
    "hero.subtitle": "将 MacBook 摄像头刘海变为丝滑流畅的 120Hz ProMotion 灵动岛。集成现代 macOS Launchpad Home、超顺滑 60Hz 硬件 HUD、Face ID 识别、锁屏播放器与全浏览器媒体控制。",
    "hero.downloadBtn": "下载 NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 验证成功",
    "chip.faceidSub": "端侧 Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "经典分页网格 • F4 与手势",
    "chip.hudTitle": "丝滑 60Hz HUD",
    "chip.hudSub": "音量、亮度与键盘背光",
    "chip.settingsTitle": "原生 HIG 设置",
    "chip.settingsSub": "实时搜索与功能导览",
    "chip.ddcTitle": "DDC 硬件显示控制",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 快充中",
    "chip.batterySub": "智能 80% 充电保护",
    "chip.shelfTitle": "刘海暂存架已就绪",
    "chip.shelfSub": "拖拽暂存 + AirDrop 隔空投送",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "待机 0% CPU 占用",
    "chip.lyricsTitle": "音乐与浏览器同步",
    "chip.lyricsSub": "Spotify、Music、YouTube 与网页",
    "chip.statsTitle": "系统监控 (Stats)",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "剪贴板记录",
    "chip.clipboardSub": "50 条记录 • 快捷 ⌘⌥V",
    "chip.lunarTitle": "农历与多国历法",
    "chip.lunarSub": "农历 • 回历 • 希伯来历",
    "chip.islandTitle": "灵动岛模式",
    "chip.islandSub": "像素级贝塞尔曲线",
    "chip.lockscreenTitle": "锁屏播放器",
    "chip.lockscreenSub": "实时播放控制与滚动歌词",
    "chip.displayTitle": "多显示器中枢",
    "chip.displaySub": "智能单刘海切换",

    // Demo Controls
    "demo.modeNotch": "MacBook 刘海",
    "demo.modeIsland": "灵动岛模式",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "同步歌词",
    "demo.pillBattery": "98W 快充",
    "demo.pillShelf": "文件暂存",
    "demo.hint": "点击或悬停于上方刘海，体验 120Hz 丝滑展开动画！",
    "notch.idle": "NotchPulse 运行中",
    "notch.faceIdScanned": "Face ID 验证成功",
    "notch.faceIdPrompt": "通过前置摄像头无感解锁 Mac",
    "notch.batteryPrompt": "18 分钟后充满 • 电池健康度: 100%",
    "notch.shelfItems": "暂存架: 3 个文件",
    "notch.shelfPrompt": "将文件拖入刘海以在应用间暂存",

    // Bento Features Section
    "features.tag": "专为 macOS 原生打造",
    "features.title": "全面释放 MacBook 刘海潜能",
    "features.subtitle": "采用 Swift 纯原生编写，待机状态 0% CPU 占用。集成 Launchpad Home、超顺滑 60Hz 硬件 HUD、Face ID 生物识别与锁屏播放器。",
    
    "feat1.title": "生物识别 Face ID 人脸解锁",
    "feat1.desc": "将 iOS 级人脸识别带入 Mac。持续感应在位状态，依靠端侧 Apple Vision 算法保障隐私，安全快速解锁应用。",
    "bento.faceidVerified": "神经网格 Face Mesh 运算中",
    "bento.faceidSub": "512D 向量嵌入 • 端侧 Apple Vision",
    "bento.faceidHandshake": "锁定屏幕至桌面零延迟极速切换",

    "feat2.title": "120Hz ProMotion 双形态切换",
    "feat2.desc": "在 MacBook 自带刘海与外接 Studio Display 显示器的居中灵动岛之间顺畅自如地切换。",
    "bento.springPhysics": "Apple 弹簧物理引擎 (响应: 0.38s)",

    "feat3.title": "同步歌词与全浏览器媒体控制",
    "feat3.desc": "为 Spotify、Apple Music、YouTube Music 及 Safari / Chrome / Arc 上的 YouTube、Netflix 提供逐词歌词与直接进度拖拽控制。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "刘海暂存架 Notch Shelf",
    "feat4.desc": "将文件、链接或截图直接拖拽至刘海边缘暂存，在各工作区与多任务间便捷流转。",
    "shelf.dropText": "拖拽文件到这里",

    "feat5.title": "多显示器中枢与 DDC 硬件控制",
    "feat5.desc": "通过 Display Hub 或 DDC/CI 直接控制内置与外接显示器硬件亮度及音量，支持光标感应 F1/F2 键位与 2.2ms 快速合并写入。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 亮度",
    "bento.ddcVolume": "内置扬声器音量",

    "feat6.title": "实时 CPU、RAM 与 GPU 监控",
    "feat6.desc": "在刘海直观掌握统一内存压力、CPU 核心频率与 GPU 占用，零待机性能损耗。",
    "bento.cpuCores": "8 核心运行中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "农历与多国历法计算引擎",
    "feat7.desc": "离线天文高精度计算：支持越南农历 (UTC+7)、中国农历 (UTC+8)、伊斯兰历、希伯来历、佛历及波斯历。一键切换农历阴阳双显。",
    "feat7.monthTitle": "2026年9月",
    "feat7.moonBadge": "农历标记",
    "feat7.eventBadge": "9月27日 (农历 17/8)",
    "feat7.eventTitle": "NotchPulse 产品发布会",
    "feat7.eventTime": "19:00 - 20:30 • 全天同步",

    "feat8.title": "智能 80% 电池健康保护",
    "feat8.desc": "底层调用 Apple Silicon SMC 电源控制器，充电锁定 80% 黄金阈值以延长电池寿命，支持一键满电 100% 模式。",

    "feat9.title": "智能剪贴板历史管理",
    "feat9.desc": "舒适 3 项直观视窗、毫秒级即时检索与 AppKit 原生滚动保护。在刘海中随选随贴代码、HEX 色码与格式化文本。",

    "feat10.title": "9 种原生本地化语言",
    "feat10.desc": "全面支持简体中文、繁体中文、英语、越南语、日语、德语、法语、西班牙语与阿拉伯语，即时响应无缝切换。",

    "feat11.title": "原生 SMC 风扇与硬件温控系统",
    "feat11.desc": "直接对接 SMC 硬件并支持自动静默 Root 提权。直接在刘海区域调节风扇转速（自动、强劲全速、静音、自定义 RPM）并实时监控芯片温度。",

    "feat12.title": "交互式音频控制中心与蓝牙电量管理",
    "feat12.desc": "直接在刘海区域即时切换音频输出与麦克风。支持各应用程序独立音量调节，并实时监控 AirPods 与蓝牙耳机电量。",
    "bento.audioOutputs": "AirPods Pro • 剩余电量 92%",
    "bento.audioApps": "独立应用音量混音 • Spotify & Safari",
    "bento.audioTabOutput": "输出",
    "bento.audioTabInput": "输入",

    "feat13.title": "macOS 系统权限与免动手 Face ID 认证",
    "feat13.desc": "自动拦截 macOS 管理员 sudo 提权、钥匙串认证与 Touch ID 提示。通过本地 Apple Vision 进行免动手面容识别，无需手动输入密码。",
    "bento.authIntercept": "终端 sudo 与钥匙串安全拦截",
    "bento.authFaceID": "Apple Vision 本地端神经网络验证",
    "bento.authStatus": "免动手无感极速认证",

    "bento.fanRpm": "4,800 RPM 强劲全速",
    "bento.fanCpuTemp": "CPU 42°C • 酷冷低噪",
    "bento.fanRootAuth": "Root 守护进程安全激活",

    "feat14.title": "现代 macOS 专属 Launchpad Home",
    "feat14.desc": "在所有 macOS 版本重现经典全屏分页启动台。支持鼠标拖拽与双指滑动翻页、文件夹管理、刘海下方实时搜索、4K/5K 外接显示器满屏比例缩放，并全面拦截 F4 按键、触发角、程序坞与四指捏合手势。",
    "bento.lpSearch": "搜索应用与文件夹 (⇧⌘L)",
    "bento.lpTabPage1": "第 1 页",
    "bento.lpTabPage2": "第 2 页",
    "bento.lpTabFolder": "文件夹",
    "bento.lpFolderUtilities": "开发工具",
    "bento.lpBadgeScaling": "4K/5K 满屏等比缩放",
    "bento.lpBadgeIntercept": "F4 • 触发角 • 四指捏合",

    "feat15.title": "超顺滑 60Hz 硬件 HUD 指示条",
    "feat15.desc": "无重叠取代系统音量、屏幕亮度、键盘背光与 MagSafe 充电 HUD。长按按键具备 60Hz 连续线性插值，支持刘海内直接拖拽调节以及精简 Inline / 展开样式。",
    "bento.hudVolumeLabel": "音量",
    "bento.hudBrightLabel": "亮度",
    "bento.hudRampBadge": "60Hz 长按连续插值",
    "bento.hudInlineBadge": "Inline 与直接拖拽",

    "feat16.title": "锁屏实时播放器与全浏览器同步",
    "feat16.desc": "直接在 macOS 锁定屏幕展示专辑封面、播放控制与按需同步歌词。流畅操控 YouTube、Netflix、Safari、Chrome、Arc、Spotify 与 Apple Music，解锁无缝衔接。",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "锁屏 HUD 与按需歌词",

    "feat17.title": "原生 macOS HIG 设置与深度搜索",
    "feat17.desc": "遵循 Apple Human Interface Guidelines：半透明 NavigationSplitView 侧边栏、自动跟随深浅外观、分组圆角卡片、NSSearchField 实时高亮搜索与交互式功能导览。",
    "bento.higSearch": "⌘ 搜索 582 项设置...",
    "bento.higRow1": "拦截 F4 与触控板手势",
    "bento.higRow2": "功能导览高亮指引",
    "bento.higBadge": "原生 HIG 零卡顿",

    // Reviews Section
    "reviews.tag": "全球社区",
    "reviews.title": "备受全球开发者好评",
    "reviews.subtitle": "来自世界各地的工程师、UI 设计师与 Mac 深度用户的真实评价。",
    "reviews.all": "所有评价 (4.8 ★)",
    "reviews.five": "5 星好评",
    "reviews.fourPointFive": "4.5 星",
    "reviews.four": "4 星",
    "reviews.threePointFive": "3.5 星",

    // Creator Section
    "creator.tag": "关于开发者",
    "creator.bio": "热爱系统架构设计与 macOS 原生开发的 ITM 学生。从零独立打造 NotchPulse，深入探索人机交互，让 MacBook 刘海变得真正优雅实用。",

    // Installation Section
    "install.tag": "准备好提升您的 Mac 体验了吗？",
    "install.title": "立即体验 NotchPulse",
    "install.subtitle": "兼容所有 macOS 版本（Monterey、Ventura、Sonoma、Sequoia 及更新系统）。针对 Apple Silicon 与 Intel 全系列 Mac 深度优化。",
    "install.btnDmg": "直接下载 NotchPulse.dmg",

    // Footer
    "footer.rights": "© 2026 NotchPulse 由 Kun Nguyen (HieuKun) 制作。保留所有权利。",
    "footer.releases": "发布版本",
    "footer.support": "支持与反馈",

    // Toast
    "toast.copied": "已将 Homebrew 安装命令复制到剪贴板！",

    // Hugo / Hani Learning
    "hugo.tag": "精选好友项目 • Hani 中文学习平台",
    "hugo.sub": "由杜孟雄 (Hugo) 创立的现代化中文学习平台",
    "hugo.btn": "注册领取 2,000 Hani 学习币"
  },

  es: {
    // Navigation
    "nav.skip": "Ir al contenido principal",
    "nav.features": "Características",
    "nav.demo": "Demo en Vivo",
    "nav.reviews": "Opiniones",
    "nav.creator": "Creador",
    "nav.download": "Descargar",
    "nav.get": "Obtener App (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} Lanzado",
    "hero.title": "El Notch de tu MacBook, reinventado.",
    "hero.titleMain": "El Notch de tu MacBook,",
    "hero.titleAccent": "reinventado.",
    "hero.subtitle": "Transforma el notch de tu MacBook en una Dynamic Island fluida a 120Hz ProMotion. Ahora con Launchpad Home para macOS moderno, HUDs continuos a 60Hz, Face ID, Reproductor en Pantalla Bloqueada y control multimedia universal.",
    "hero.downloadBtn": "Descargar NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Verificado",
    "chip.faceidSub": "Neural Engine en el Dispositivo",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "Cuadrícula Clásica • F4 y Pellizco",
    "chip.hudTitle": "HUDs Suaves 60Hz",
    "chip.hudSub": "Volumen, Brillo y Retroiluminación",
    "chip.settingsTitle": "Ajustes Nativos HIG",
    "chip.settingsSub": "Búsqueda en Vivo y Tour Guiado",
    "chip.ddcTitle": "Control DDC de Pantallas",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Activo",
    "chip.batterySub": "Protección inteligente al 80%",
    "chip.shelfTitle": "Notch Shelf Listo",
    "chip.shelfSub": "Arrastrar y Soltar + AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% de CPU en reposo",
    "chip.lyricsTitle": "Música y Navegadores",
    "chip.lyricsSub": "Spotify, Music, YouTube y Web",
    "chip.statsTitle": "Monitor del Sistema",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "Portapapeles",
    "chip.clipboardSub": "50 elementos • ⌘⌥V",
    "chip.lunarTitle": "Cal Lunar y Regional",
    "chip.lunarSub": "Lunar • Hijri • Hebreo",
    "chip.islandTitle": "Modo Dynamic Island",
    "chip.islandSub": "Curva Bézier Perfecta",
    "chip.lockscreenTitle": "Pantalla Bloqueada",
    "chip.lockscreenSub": "Controles y Letras en Vivo",
    "chip.displayTitle": "Hub Multipantalla",
    "chip.displaySub": "Sincronización Inteligente",

    // Demo Controls
    "demo.modeNotch": "MacBook Notch",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Letras en Vivo",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "Notch Shelf",
    "demo.hint": "¡Haz clic o pasa el cursor sobre el notch para ver la animación fluida a 120Hz!",
    "notch.idle": "NotchPulse Activo",
    "notch.faceIdScanned": "Face ID Verificado",
    "notch.faceIdPrompt": "Mac desbloqueado vía cámara frontal",
    "notch.batteryPrompt": "Carga completa en 18 minutos • Salud de batería: 100%",
    "notch.shelfItems": "Notch Shelf: 3 Archivos",
    "notch.shelfPrompt": "Arrastra archivos al notch para guardarlos temporalmente",

    // Bento Features Section
    "features.tag": "Diseñado para macOS",
    "features.title": "Maximiza el Potencial del Notch en tu Mac",
    "features.subtitle": "Creado nativamente en Swift con 0% de uso de CPU en reposo. Incluye Launchpad Home, HUDs fluidos de 60Hz, Face ID biométrico, reproductor en pantalla bloqueada y herramientas inteligentes.",
    
    "feat1.title": "Reconocimiento Facial Face ID",
    "feat1.desc": "Lleva el desbloqueo facial estilo iOS a tu Mac. Detección continua de presencia y desbloqueo seguro con Apple Vision en el propio dispositivo.",
    "bento.faceidVerified": "Malla Facial Neuronal Activa",
    "bento.faceidSub": "Incrustación vectorial 512D • Apple Vision en el dispositivo",
    "bento.faceidHandshake": "Transición sin retardo de pantalla de bloqueo a escritorio",

    "feat2.title": "Modo Dual 120Hz Notch & Isla",
    "feat2.desc": "Cambia con total fluidez entre el notch integrado de la MacBook y una Dynamic Island centrada en monitores externos.",
    "bento.springPhysics": "Física de resortes de Apple (respuesta: 0.38s)",

    "feat3.title": "Letras en Vivo y Multimedia Universal",
    "feat3.desc": "Letras palabra por palabra y control directo para Spotify, Apple Music, YouTube Music y navegadores web (YouTube y Netflix en Safari, Chrome y Arc) con búsqueda directa en línea de tiempo.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf y Arrastre Rápido",
    "feat4.desc": "Arrastra archivos, enlaces o capturas directamente a la muesca del notch para guardarlos temporalmente entre espacios.",
    "shelf.dropText": "Suelta los archivos aquí",

    "feat5.title": "Hub Multipantalla y Control DDC",
    "feat5.desc": "Ajusta brillo y volumen de pantallas integradas y externas desde el Display Hub o vía DDC/CI con teclas F1/F2 conscientes del cursor y coalescencia de 2,2ms.",
    "bento.ddcBrightness": "Brillo Dell UltraSharp 4K",
    "bento.ddcVolume": "Volumen de Audio Integrado",

    "feat6.title": "Monitor de Sistema CPU, RAM y GPU",
    "feat6.desc": "Telemetría de hardware en tiempo real en el notch: presión de memoria unificada, núcleos de CPU y carga de GPU sin consumo en reposo.",
    "bento.cpuCores": "8 Núcleos Activos",
    "bento.ramUsage": "10.3 / 16 GB Activo",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "Calendario Lunar Regional y Multipaís",
    "feat7.desc": "Cálculo astronómico sin conexión para calendario lunar vietnamita (UTC+7), chino (UTC+8), islámico, hebreo, budista y persa con vista de fechas lunares.",
    "feat7.monthTitle": "Septiembre 2026",
    "feat7.moonBadge": "Cal Lunar",
    "feat7.eventBadge": "27 Sep (17/8 Cal Lunar)",
    "feat7.eventTitle": "Lanzamiento de NotchPulse",
    "feat7.eventTime": "19:00 - 20:30 • Sincronización",

    "feat8.title": "Protección Inteligente de Batería al 80%",
    "feat8.desc": "Control directo de SMC en Apple Silicon. Limita la carga al 80% para evitar la degradación de la batería con modo rápido al 100%.",

    "feat9.title": "Gestor Inteligente de Portapapeles",
    "feat9.desc": "Cómoda vista de 3 elementos, búsqueda instantánea y protección de desplazamiento AppKit nativa. Copia snippets, códigos HEX y texto desde el notch.",

    "feat10.title": "Localización Nativa en 9 Idiomas",
    "feat10.desc": "Interfaz completamente traducida a inglés, vietnamita, chino (trad./simp.), japonés, alemán, francés, español y árabe en tiempo real.",

    "feat11.title": "Control Nativo de Ventiladores SMC y Térmica",
    "feat11.desc": "Control directo de hardware SMC con autorización root automática. Gestiona velocidades de ventilador (Auto, Max, Silencioso, RPM personalizado) y temperatura en tiempo real.",

    "feat12.title": "Centro de Audio Interactivo y Batería Bluetooth",
    "feat12.desc": "Cambia dispositivos de salida y micrófonos al instante desde el notch. Gestiona el volumen por aplicación y monitorea la batería de AirPods y auriculares Bluetooth en tiempo real.",
    "bento.audioOutputs": "AirPods Pro • 92% Batería",
    "bento.audioApps": "Mezclador por App • Spotify y Safari",
    "bento.audioTabOutput": "Salida",
    "bento.audioTabInput": "Entrada",

    "feat13.title": "Autenticación del Sistema macOS y Face ID Manos Libres",
    "feat13.desc": "Intercepta solicitudes de sudo, accesos a Llaveros y avisos de Touch ID en macOS. Autenticación biométrica fluida con Apple Vision en el dispositivo sin escribir contraseñas.",
    "bento.authIntercept": "Intercepción de sudo y Llaveros",
    "bento.authFaceID": "Verificación Biométrica Apple Vision",
    "bento.authStatus": "Autenticado con Manos Libres",

    "bento.fanRpm": "4.800 RPM Turbo",
    "bento.fanCpuTemp": "CPU 42°C • Fresco y Silencioso",
    "bento.fanRootAuth": "Daemon Root Seguro Activo",

    "feat14.title": "Launchpad Home para macOS Moderno",
    "feat14.desc": "Devuelve la clásica cuadrícula de apps a pantalla completa en cualquier macOS. Paginación al arrastrar con el ratón o deslizar con dos dedos, carpetas, búsqueda bajo el notch, escalado proporcional en 4K/5K e intercepción total de F4, Esquinas Activas, Dock y pellizco.",
    "bento.lpSearch": "Buscar apps y carpetas (⇧⌘L)",
    "bento.lpTabPage1": "Página 1",
    "bento.lpTabPage2": "Página 2",
    "bento.lpTabFolder": "Carpeta",
    "bento.lpFolderUtilities": "Herramientas",
    "bento.lpBadgeScaling": "Escalado Pantalla Completa 4K/5K",
    "bento.lpBadgeIntercept": "F4 • Esquina • Pellizco 4 Dedos",

    "feat15.title": "HUDs de Hardware Ultrafluidos a 60Hz",
    "feat15.desc": "Reemplaza los HUDs de Volumen, Brillo, Teclado y MagSafe sin superposiciones del sistema. Interpolación continua a 60Hz al mantener pulsadas las teclas, ajuste táctil en el notch y estilos Inline o Abierto.",
    "bento.hudVolumeLabel": "Volumen",
    "bento.hudBrightLabel": "Brillo",
    "bento.hudRampBadge": "Rampa Continua 60Hz",
    "bento.hudInlineBadge": "Inline y Deslizamiento",

    "feat16.title": "Pantalla Bloqueada y Control de Navegador",
    "feat16.desc": "Muestra carátulas, controles de reproducción y letras bajo demanda directamente en la Pantalla Bloqueada de macOS. Controla YouTube, Netflix, Safari, Chrome, Arc, Spotify y Apple Music sin cortes al desbloquear.",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "HUD Bloqueo y Letras Bajo Demanda",

    "feat17.title": "Ajustes Nativos HIG y Búsqueda Profunda",
    "feat17.desc": "Diseñado según las Apple HIG: barra lateral translúcida con NavigationSplitView, modo Claro/Oscuro automático, tarjetas agrupadas, búsqueda en vivo con resaltado NSSearchField y Tour interactivo.",
    "bento.higSearch": "⌘ Buscar 582 ajustes...",
    "bento.higRow1": "Interceptar F4 y Gestos",
    "bento.higRow2": "Foco del Tour de Funciones",
    "bento.higBadge": "HIG Nativo Fluido",

    // Reviews Section
    "reviews.tag": "Comunidad Global",
    "reviews.title": "Elogiado por Desarrolladores del Mundo",
    "reviews.subtitle": "Opiniones reales de ingenieros, diseñadores y creadores de Mac de todo el planeta.",
    "reviews.all": "Todas las Opiniones (4.8 ★)",
    "reviews.five": "5 Estrellas",
    "reviews.fourPointFive": "4.5 Estrellas",
    "reviews.four": "4 Estrellas",
    "reviews.threePointFive": "3.5 Estrellas",

    // Creator Section
    "creator.tag": "Conoce al Creador",
    "creator.bio": "Estudiante de ITM apasionado por el diseño de sistemas y las arquitecturas nativas de macOS. Creó NotchPulse desde cero para explorar la interacción persona-ordenador y hacer el notch útil y placentero.",

    // Installation Section
    "install.tag": "¿Listo para elevar tu Mac?",
    "install.title": "Obtén NotchPulse Hoy",
    "install.subtitle": "Compatible con todas las versiones de macOS (Monterey, Ventura, Sonoma, Sequoia y posteriores). Optimizado para todos los Mac (Apple Silicon e Intel).",
    "install.btnDmg": "Descargar NotchPulse.dmg (Directo)",

    // Footer
    "footer.rights": "© 2026 NotchPulse por Kun Nguyen (HieuKun). Todos los derechos reservados.",
    "footer.releases": "Versiones",
    "footer.support": "Soporte",

    // Toast
    "toast.copied": "¡Comando Homebrew copiado al portapapeles!",

    // Hugo / Hani Learning
    "hugo.tag": "Proyecto Amigo • Aprende Chino con Hani",
    "hugo.sub": "Plataforma moderna de aprendizaje de chino fundada por Do Manh Hung (Hugo)",
    "hugo.btn": "Regístrate y recibe 2,000 monedas Hani"
  },

  fr: {
    // Navigation
    "nav.skip": "Aller au contenu principal",
    "nav.features": "Fonctionnalités",
    "nav.demo": "Démo Live",
    "nav.reviews": "Avis",
    "nav.creator": "Créateur",
    "nav.download": "Télécharger",
    "nav.get": "Obtenir l'app (DMG)",

    // Hero
    "hero.badge": "NotchPulse {version} Disponible",
    "hero.title": "L'encoche MacBook, réinventée.",
    "hero.titleMain": "L'encoche MacBook,",
    "hero.titleAccent": "Réinventée.",
    "hero.subtitle": "Transformez l'encoche de votre MacBook en une Dynamic Island fluide à 120Hz ProMotion. Inclut Launchpad Home pour macOS moderne, des HUDs ultra-fluides à 60Hz, Face ID biométrique, lecteur sur écran verrouillé et contrôle universel des navigateurs.",
    "hero.downloadBtn": "Télécharger NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Ondes Lofi",

    // Chips
    "chip.faceidTitle": "Face ID Vérifié",
    "chip.faceidSub": "Neural Engine sur l'appareil",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "Grille classique • F4 & Pincement",
    "chip.hudTitle": "HUDs fluides 60Hz",
    "chip.hudSub": "Volume, Luminosité & Clavier",
    "chip.settingsTitle": "Réglages natifs HIG",
    "chip.settingsSub": "Recherche en direct & Visite guidée",
    "chip.ddcTitle": "Contrôle écran DDC",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "MagSafe 98W Actif",
    "chip.batterySub": "Limite intelligente 80% protégée",
    "chip.shelfTitle": "Étagère Notch prête",
    "chip.shelfSub": "Glisser-déposer + AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU en veille",
    "chip.lyricsTitle": "Paroles & Navigateurs",
    "chip.lyricsSub": "Spotify, Music, YouTube & Web",
    "chip.statsTitle": "Moniteur système",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "Historique presse-papiers",
    "chip.clipboardSub": "50 éléments • Raccourci ⌘⌥V",
    "chip.lunarTitle": "Calendriers lunaires",
    "chip.lunarSub": "Âm Lịch • Hijri • Hébreu",
    "chip.islandTitle": "Mode Dynamic Island",
    "chip.islandSub": "Courbes de Bézier précises",
    "chip.lockscreenTitle": "Lecteur écran verrouillé",
    "chip.lockscreenSub": "Contrôles live & Paroles",
    "chip.displayTitle": "Hub Multi-Écrans",
    "chip.displaySub": "Synchronisation fluide double écran",

    // Demo Controls & Notch
    "demo.modeNotch": "Encoche MacBook",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Paroles Sync",
    "demo.pillBattery": "MagSafe 98W",
    "demo.pillShelf": "Étagère Notch",
    "demo.hint": "Cliquez ou survolez l'encoche ci-dessus pour déclencher l'animation 120Hz !",
    "notch.idle": "NotchPulse Actif",
    "notch.faceIdScanned": "Face ID Vérifié",
    "notch.faceIdPrompt": "Mac déverrouillé instantanément via la caméra frontale",
    "notch.batteryPrompt": "Charge complète dans 18 min • Santé : 100%",
    "notch.shelfItems": "Étagère : 3 éléments",
    "notch.shelfPrompt": "Déposez des fichiers ici pour les garder sous la main",

    // Bento Features Section
    "features.tag": "Conçu pour macOS",
    "features.title": "Boostez l'encoche de votre MacBook",
    "features.subtitle": "Développé nativement en Swift avec 0% de CPU au repos. Profitez de Launchpad Home, des HUDs 120Hz & 60Hz, de Face ID biométrique, du lecteur sur écran verrouillé et d'outils intelligents.",

    "feat1.title": "Reconnaissance Biométrique Face ID",
    "feat1.desc": "Apporte la reconnaissance faciale de niveau iOS sur votre Mac. Détecte votre présence en continu et déverrouille vos apps avec un traitement local Apple Vision respectueux de votre vie privée.",
    "bento.faceidVerified": "Maillage Facial Neural Actif",
    "bento.faceidSub": "Vecteur 512D • Apple Vision sur l'appareil",
    "bento.faceidHandshake": "Transition sans latence de l'écran verrouillé au bureau",

    "feat2.title": "Double Mode 120Hz ProMotion",
    "feat2.desc": "Alterne avec fluidité entre l'encoche native du MacBook et une Dynamic Island flottante centrée sur les Studio Displays externes.",
    "bento.springPhysics": "Physique ressort (réponse : 0,38s)",

    "feat3.title": "Paroles Synchronisées & Médias Universels",
    "feat3.desc": "Paroles mot à mot en direct et contrôles pour Spotify, Apple Music, YouTube Music et navigateurs (YouTube, Netflix sur Safari, Chrome & Arc) avec pochette dynamique.",
    "bento.songLyrics": "\"Dérivant doucement à travers les sons calmes de la nuit...\"",

    "feat4.title": "Étagère Notch & Dépôt Rapide",
    "feat4.desc": "Glissez fichiers, liens ou captures d'écran directement dans l'encoche pour les conserver temporairement entre vos bureaux et apps.",
    "shelf.dropText": "Déposez vos fichiers ici",

    "feat5.title": "Hub Multi-Écrans & HUD Matériel DDC",
    "feat5.desc": "Contrôlez la luminosité matérielle et le volume de vos écrans internes et externes via DDC/CI avec touches F1/F2 intelligentes.",
    "bento.ddcBrightness": "Luminosité Dell UltraSharp 4K",
    "bento.ddcVolume": "Volume Audio Intégré",

    "feat6.title": "Moniteur CPU, RAM & GPU en Direct",
    "feat6.desc": "Télémétrie matérielle en temps réel dans l'encoche. Suivez la mémoire unifiée Apple Silicon, les cœurs CPU et la charge GPU avec 0% d'impact au repos.",
    "bento.cpuCores": "8 Cœurs Actifs",
    "bento.ramUsage": "10,3 / 16 Go Actifs",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "Calendriers Lunaires & Multi-Régions",
    "feat7.desc": "Calcul astronomique hors ligne pour le calendrier lunaire vietnamien (UTC+7), chinois (UTC+8), islamique hégirien, hébraïque, bouddhiste et persan.",
    "feat7.monthTitle": "Septembre 2026",
    "feat7.moonBadge": "Cal. Lunaire",
    "feat7.eventBadge": "27 Sep (17/8 Cal. Lunaire)",
    "feat7.eventTitle": "Lancement NotchPulse",
    "feat7.eventTime": "19:00 - 20:30 • Synchro Journée",

    "feat8.title": "Protection Batterie Intelligente 80%",
    "feat8.desc": "Contrôleur d'alimentation SMC direct pour Apple Silicon. Plafonne la charge à 80% pour préserver les cycles, avec option 100% en un clic.",

    "feat9.title": "Presse-papiers Intelligent",
    "feat9.desc": "Vue confortable sur 3 éléments, recherche instantanée et protection AppKit. Copiez extraits de code, couleurs hexadécimales et texte formaté depuis l'encoche.",

    "feat10.title": "Localisation Native en 9 Langues",
    "feat10.desc": "Interface native traduite en 9 langues : English, Tiếng Việt, 繁體中文, 简体中文, 日本語, Deutsch, Français, Español et العربية avec bascule instantanée.",

    "feat11.title": "Contrôle Ventilateurs SMC & Thermique",
    "feat11.desc": "Pilote matériel SMC direct avec autorisation root automatique. Réglez les ventilateurs (Auto, Turbo, Silencieux, RPM personnalisé) et suivez les capteurs CPU/GPU.",

    "feat12.title": "Hub Audio Interactif & Batterie Bluetooth",
    "feat12.desc": "Changez de sortie et microphone dans l'encoche, ajustez le volume par application et suivez la batterie des AirPods et casques Bluetooth en temps réel.",
    "bento.audioOutputs": "AirPods Pro • 92% Batterie",
    "bento.audioApps": "Mixeur par App • Spotify & Safari",
    "bento.audioTabOutput": "Sortie",
    "bento.audioTabInput": "Entrée",

    "feat13.title": "Auth Système macOS & Face ID Mains Libres",
    "feat13.desc": "Intercepte les demandes sudo, Trousseau et Touch ID sur macOS. Authentification biométrique fluide sur l'appareil sans saisir de mot de passe.",
    "bento.authIntercept": "Interception Terminal sudo & Trousseau",
    "bento.authFaceID": "Vérification biométrique Apple Vision",
    "bento.authStatus": "Authentifié Mains Libres",

    "bento.fanRpm": "4 800 RPM Turbo",
    "bento.fanCpuTemp": "CPU 42°C • Frais & Silencieux",
    "bento.fanRootAuth": "Démon Root Auto Actif",

    "feat14.title": "Launchpad Home pour macOS Moderne",
    "feat14.desc": "Restaure la grille d'apps plein écran classique sur chaque version de macOS : glisser-déposer, balayage 2 doigts, dossiers, recherche instantanée, mise à l'échelle 4K/5K et interception F4 / Dock / pincement.",
    "bento.lpSearch": "Rechercher apps & dossiers (⇧⌘L)",
    "bento.lpTabPage1": "Page 1",
    "bento.lpTabPage2": "Page 2",
    "bento.lpTabFolder": "Dossier",
    "bento.lpFolderUtilities": "Outils Dev",
    "bento.lpBadgeScaling": "Mise à l'échelle 4K/5K bord à bord",
    "bento.lpBadgeIntercept": "F4 • Coin actif • Pincement 4 doigts",

    "feat15.title": "HUDs Matériels 60Hz Ultra-Fluides",
    "feat15.desc": "Remplace les HUDs Volume, Luminosité, Rétroéclairage clavier et MagSafe sans doublons. Interpolation continue 60Hz et réglages Inline ou Encoche ouverte.",
    "bento.hudVolumeLabel": "Volume",
    "bento.hudBrightLabel": "Luminosité",
    "bento.hudRampBadge": "Rampe continue 60Hz",
    "bento.hudInlineBadge": "Inline & Balayage",

    "feat16.title": "Lecteur Live sur Écran Verrouillé",
    "feat16.desc": "Affiche la pochette, les commandes de lecture et les paroles synchronisées directement sur l'écran verrouillé macOS pour YouTube, Netflix, Safari, Chrome, Arc, Spotify et Apple Music.",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "HUD Écran Verrouillé & Paroles à la demande",

    "feat17.title": "Réglages Natifs HIG & Recherche Profonde",
    "feat17.desc": "Conçu selon les Apple HIG : barre latérale translucide NavigationSplitView, mode Clair/Sombre auto, cartes groupées, recherche temps réel et visite guidée interactive.",
    "bento.higSearch": "⌘ Rechercher parmi 582 réglages...",
    "bento.higRow1": "Interception F4 & Pincement",
    "bento.higRow2": "Visite guidée Spotlight",
    "bento.higBadge": "HIG sans latence",

    // Reviews Section
    "reviews.tag": "Communauté Mondiale",
    "reviews.title": "Apprécié dans le Monde Entier",
    "reviews.subtitle": "Retours authentiques d'ingénieurs Mac, designers et créateurs à travers le monde.",
    "reviews.all": "Tous les avis (4,8 ★)",
    "reviews.five": "5 Étoiles",
    "reviews.fourPointFive": "4,5 Étoiles",
    "reviews.four": "4 Étoiles",

    // Creator Section
    "creator.tag": "Rencontrez le Créateur",
    "creator.bio": "Étudiant ITM passionné par la conception système et les architectures natives macOS. A conçu NotchPulse de zéro pour rendre l'encoche du MacBook véritablement utile et élégante.",

    // Installation Section
    "install.tag": "Prêt à sublimer votre Mac ?",
    "install.title": "Obtenez NotchPulse Aujourd'hui",
    "install.subtitle": "Compatible avec toutes les versions de macOS (Monterey, Ventura, Sonoma, Sequoia & plus récentes) sur Apple Silicon et Mac Intel.",
    "install.btnDmg": "Télécharger NotchPulse.dmg (Direct)",

    // Footer
    "footer.rights": "© 2026 NotchPulse par Kun Nguyen (HieuKun). Tous droits réservés.",
    "footer.releases": "Versions",
    "footer.support": "Support",

    // Toast
    "toast.copied": "Commande Homebrew copiée dans le presse-papiers !",

    // Hugo / Hani Learning
    "hugo.tag": "Projet Ami • Apprenez le Chinois avec Hani",
    "hugo.sub": "Plateforme moderne d'apprentissage du chinois fondée par Do Manh Hung (Hugo)",
    "hugo.btn": "S'inscrire & Recevoir 2 000 pièces Hani"
  },

  ar: {
    // Navigation
    "nav.skip": "انتقل إلى المحتوى الرئيسي",
    "nav.features": "المميزات",
    "nav.demo": "تجربة مباشرة",
    "nav.reviews": "التقييمات",
    "nav.creator": "المطور",
    "nav.download": "تحميل",
    "nav.get": "تحميل التطبيق (DMG)",

    // Hero
    "hero.badge": "إصدار NotchPulse {version} متاح الآن",
    "hero.title": "نتوء MacBook بمفهوم جديد.",
    "hero.titleMain": "نتوء MacBook،",
    "hero.titleAccent": "بمفهوم جديد.",
    "hero.subtitle": "حوّل نتوء كاميرا MacBook إلى Dynamic Island سلسة بتردد 120Hz ProMotion. يشمل Launchpad Home لنظام macOS الحديث، ومؤشرات 60Hz فائقة السلاسة، وبصمة الوجه Face ID، ومشغل شاشة القفل، والتحكم الشامل بالمتصفحات.",
    "hero.downloadBtn": "تحميل NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — أمواج Lofi",

    // Chips
    "chip.faceidTitle": "توثيق Face ID",
    "chip.faceidSub": "معالجة محلية عبر Neural Engine",
    "chip.launchpadTitle": "Launchpad Home",
    "chip.launchpadSub": "شبكة التطبيقات الكلاسيكية • F4",
    "chip.hudTitle": "مؤشرات 60Hz سلسة",
    "chip.hudSub": "الصوت والسطوع وإضاءة لوحة المفاتيح",
    "chip.settingsTitle": "إعدادات HIG أصلية",
    "chip.settingsSub": "بحث فوري وجولة تعريفية",
    "chip.ddcTitle": "تحكم الشاشة DDC",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "شحن MagSafe 98W نشط",
    "chip.batterySub": "حماية الشحن الذكية عند 80%",
    "chip.shelfTitle": "رف الملفات السريع",
    "chip.shelfSub": "سحب وإفلات + مشاركة AirDrop",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "استهلاك 0% للمعالج في الخمول",
    "chip.lyricsTitle": "مزامنة الكلمات والمتصفح",
    "chip.lyricsSub": "Spotify, Music, YouTube والويب",
    "chip.statsTitle": "مراقب النظام",
    "chip.statsSub": "4.2% CPU • 18GB RAM",
    "chip.clipboardTitle": "سجل الحافظة",
    "chip.clipboardSub": "50 عنصراً • اختصار ⌘⌥V",
    "chip.lunarTitle": "التقاويم القمرية والمتعددة",
    "chip.lunarSub": "هجري • قمري • عبري",
    "chip.islandTitle": "وضع Dynamic Island",
    "chip.islandSub": "منحنيات بيزيه دقيقة للغاية",
    "chip.lockscreenTitle": "مشغل شاشة القفل",
    "chip.lockscreenSub": "تحكم مباشر وكلمات الأغاني",
    "chip.displayTitle": "مركز الشاشات المتعددة",
    "chip.displaySub": "مزامنة سلسة للشاشات الخارجية",

    // Demo Controls & Notch
    "demo.modeNotch": "نتوء MacBook",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "كلمات متزامنة",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "رف النتوء",
    "demo.hint": "انقر أو مرر المؤشر فوق النتوء لتجربة التوسع السلس بتردد 120Hz!",
    "notch.idle": "NotchPulse نشط",
    "notch.faceIdScanned": "تم التحقق عبر Face ID",
    "notch.faceIdPrompt": "تم فتح الماك بسلاسة عبر الكاميرا الأمامية",
    "notch.batteryPrompt": "يكتمل خلال 18 دقيقة • صحة البطارية: 100%",
    "notch.shelfItems": "الرف: 3 عناصر",
    "notch.shelfPrompt": "أفلت الملفات داخل النتوء لحفظها مؤقتاً",

    // Bento Features Section
    "features.tag": "مصمم لنظام macOS",
    "features.title": "ارتقِ بتجربة نتوء MacBook",
    "features.subtitle": "مبني بالكامل بلغة Swift الأصلية بدون أي استهلاك للمعالج في وضع الخمول. يجمع Launchpad Home ومؤشرات 120Hz و 60Hz وبصمة Face ID ومشغل شاشة القفل.",

    "feat1.title": "التعرف البيومتري Face ID",
    "feat1.desc": "يجلب دقة التعرف على الوجه من iOS إلى جهاز Mac. يستشعر حضورك تلقائياً ويفتح التطبيقات المحمية محلياً عبر Apple Vision مع الحفاظ التام على الخصوصية.",
    "bento.faceidVerified": "الشبكة العصبية للوجه نشطة",
    "bento.faceidSub": "تضمين 512D • معالجة محلية Apple Vision",
    "bento.faceidHandshake": "انتقال فوري من شاشة القفل إلى سطح المكتب",

    "feat2.title": "وضع 120Hz ProMotion المزدوج",
    "feat2.desc": "يتحول بانسيابية بين نتوء MacBook الأصلي وDynamic Island العائمة في منتصف شاشات Studio Display الخارجية.",
    "bento.springPhysics": "فيزياء نابضية (الاستجابة: 0.38 ثانية)",

    "feat3.title": "كلمات أغاني متزامنة ووسائط شاملة",
    "feat3.desc": "عرض الكلمات كلمة بكلمة والتحكم بالتشغيل لـ Spotify وApple Music وYouTube Music والمتصفحات (YouTube وNetflix على Safari وChrome وArc).",
    "bento.songLyrics": "\"تنجرف الألحان بهدوء عبر سكون الليل...\"",

    "feat4.title": "رف الملفات والإفلات السريع",
    "feat4.desc": "اسحب الملفات أو الروابط أو لقطات الشاشة مباشرة إلى النتوء لحفظها مؤقتاً والتنقل بها بين المساحات والتطبيقات.",
    "shelf.dropText": "أفلت الملفات هنا",

    "feat5.title": "مركز الشاشات ومؤشرات DDC",
    "feat5.desc": "تحكم في سطوع وصوت الشاشة الداخلية والشاشات الخارجية عبر DDC/CI باستخدام مفاتيح F1/F2 حسب موضع المؤشر.",
    "bento.ddcBrightness": "سطوع Dell UltraSharp 4K",
    "bento.ddcVolume": "مستوى الصوت المدمج",

    "feat6.title": "مراقبة CPU وRAM وGPU مباشرة",
    "feat6.desc": "قياسات عتاد فورية داخل النتوء. تابع ضغط الذاكرة الموحدة لـ Apple Silicon وأنوية المعالج واستهلاك GPU بدون استهلاك في الخمول.",
    "bento.cpuCores": "8 أنوية نشطة",
    "bento.ramUsage": "10.3 / 16 GB مستخدمة",
    "bento.gpuFps": "120 FPS Metal Pro",

    "feat7.title": "التقويم الهجري والقمري المتعدد",
    "feat7.desc": "حساب فلكي دون إنترنت للتقويم الهجري الإسلامي والقمري الفيتنامي والصيني والعبري والبوذي والفارسي مع عرض التواريخ اليومية في شبكة الشهر.",
    "feat7.monthTitle": "سبتمبر 2026",
    "feat7.moonBadge": "التقويم القمري",
    "feat7.eventBadge": "27 سبتمبر (17/8 قمري)",
    "feat7.eventTitle": "إطلاق NotchPulse",
    "feat7.eventTime": "19:00 - 20:30 • مزامنة كاملة",

    "feat8.title": "حماية البطارية الذكية عند 80%",
    "feat8.desc": "تحكم مباشر في طاقة Apple Silicon SMC لإيقاف الشحن عند 80% والحفاظ على عمر البطارية مع زر شحن كامل بضغطة واحدة.",

    "feat9.title": "مدير الحافظة الذكي",
    "feat9.desc": "عرض مريح لـ 3 عناصر مع بحث فوري وحماية التمرير. انسخ الأكواد وألوان Hex والنصوص المنسقة مباشرة من النتوء.",

    "feat10.title": "دعم أصلي لـ 9 لغات عالمية",
    "feat10.desc": "واجهة مترجمة بالكامل بـ 9 لغات: الإنجليزية والفيتنامية والصينية التقليدية والمبسطة واليابانية والألمانية والفرنسية والإسبانية والعربية مع تبديل فوري.",

    "feat11.title": "التحكم في المراوح والحرارة عبر SMC",
    "feat11.desc": "تحكم مباشر في سرعة المراوح (تلقائي، أقصى سرعة، صامت، أو سرعة مخصصة) ومراقبة مستشعرات حرارة CPU وGPU من النتوء.",

    "feat12.title": "مركز الصوت وبطارية Bluetooth",
    "feat12.desc": "بدّل مخارج الصوت والميكروفون داخل النتوء، وتحكم بمستوى صوت كل تطبيق وتابع بطارية AirPods وسماعات Bluetooth لحظياً.",
    "bento.audioOutputs": "AirPods Pro • البطارية 92%",
    "bento.audioApps": "مازج الصوت للتطبيقات • Spotify وSafari",
    "bento.audioTabOutput": "الإخراج",
    "bento.audioTabInput": "الإدخال",

    "feat13.title": "توثيق النظام عبر Face ID بدون لمس",
    "feat13.desc": "يعترض نوافذ sudo وسلسلة المفاتيح وTouch ID في macOS ليقوم بالتوثيق تلقائياً عبر بصمة الوجه دون كتابة كلمات المرور.",
    "bento.authIntercept": "اعتراض Terminal sudo وسلسلة المفاتيح",
    "bento.authFaceID": "تحقق بيومتري عبر Apple Vision",
    "bento.authStatus": "تم التوثيق بدون استخدام اليدين",

    "bento.fanRpm": "4,800 RPM توربو",
    "bento.fanCpuTemp": "المعالج 42°C • بارد وهادئ",
    "bento.fanRootAuth": "خدمة Root التلقائية نشطة",

    "feat14.title": "Launchpad Home لنظام macOS الحديث",
    "feat14.desc": "يعيد شبكة التطبيقات الكلاسيكية بملء الشاشة على جميع إصدارات macOS مع السحب والإفلات، التمرير بإصبعين، المجلدات، البحث السريع، ودعم شاشات 4K/5K واختصار F4 والقرص.",
    "bento.lpSearch": "ابحث في التطبيقات والمجلدات (⇧⌘L)",
    "bento.lpTabPage1": "صفحة 1",
    "bento.lpTabPage2": "صفحة 2",
    "bento.lpTabFolder": "مجلد",
    "bento.lpFolderUtilities": "أدوات التطوير",
    "bento.lpBadgeScaling": "ملاءمة 4K/5K من الحافة للحافة",
    "bento.lpBadgeIntercept": "F4 • الزاوية الساخنة • قرص 4 أصابع",

    "feat15.title": "مؤشرات 60Hz فائقة السلاسة",
    "feat15.desc": "يستبدل مؤشرات الصوت والسطوع وإضاءة لوحة المفاتيح وMagSafe في macOS بانسيابية 60Hz ودعم السحب المباشر ونمط Inline.",
    "bento.hudVolumeLabel": "الصوت",
    "bento.hudBrightLabel": "السطوع",
    "bento.hudRampBadge": "تدرج مستمر 60Hz",
    "bento.hudInlineBadge": "مدمج وتفاعلي",

    "feat16.title": "مشغل مباشر على شاشة القفل",
    "feat16.desc": "يعرض غلاف الألبوم وأزرار التحكم وكلمات الأغاني مباشرة على شاشة القفل لـ YouTube وNetflix وSafari وChrome وArc وSpotify وApple Music.",
    "bento.lsSourceBadge": "Safari • YouTube • Music",
    "bento.lsLyricsStatus": "واجهة شاشة القفل والكلمات عند الطلب",

    "feat17.title": "إعدادات macOS أصلية وبحث عميق",
    "feat17.desc": "مصممة وفق معايير Apple HIG: شريط جانبي شفاف، مظهر فاتح/داكن تلقائي، بطاقات مجمعة، بحث فوري، وجولة تعليمية تفاعلية.",
    "bento.higSearch": "⌘ ابحث في 582 إعداداً...",
    "bento.higRow1": "اعتراض F4 وإيماءة القرص",
    "bento.higRow2": "جولة الميزات التفاعلية",
    "bento.higBadge": "واجهة HIG فورية",

    // Reviews Section
    "reviews.tag": "مجتمع عالمي",
    "reviews.title": "محبوب من المستخدمين حول العالم",
    "reviews.subtitle": "آراء حقيقية من مهندسي ومصممي ومبدعي أجهزة Mac في مختلف أنحاء العالم.",
    "reviews.all": "جميع التقييمات (4.8 ★)",
    "reviews.five": "5 نجوم",
    "reviews.fourPointFive": "4.5 نجوم",
    "reviews.four": "4 نجوم",

    // Creator Section
    "creator.tag": "تعرّف على المطور",
    "creator.bio": "طالب ITM شغوف بتصميم الأنظمة وهندسة macOS الأصلية. طوّر NotchPulse من الصفر لاستكشاف التفاعل بين الإنسان والحاسوب وجعل نتوء MacBook مفيداً وممتعاً.",

    // Installation Section
    "install.tag": "جاهز للارتقاء بجهاز Mac الخاص بك؟",
    "install.title": "احصل على NotchPulse اليوم",
    "install.subtitle": "متوافق مع جميع إصدارات macOS (Monterey وVentura وSonoma وSequoia والأحدث) على معالجات Apple Silicon وIntel.",
    "install.btnDmg": "تحميل NotchPulse.dmg (مباشر)",

    // Footer
    "footer.rights": "© 2026 NotchPulse بواسطة Kun Nguyen (HieuKun). جميع الحقوق محفوظة.",
    "footer.releases": "الإصدارات",
    "footer.support": "الدعم",

    // Toast
    "toast.copied": "تم نسخ أمر Homebrew إلى الحافظة!",

    // Hugo / Hani Learning
    "hugo.tag": "مشروع صديق مميز • تعلّم الصينية مع Hani",
    "hugo.sub": "منصة حديثة لتعلّم اللغة الصينية أسسها Do Manh Hung (Hugo)",
    "hugo.btn": "سجّل واحصل على 2,000 عملة Hani"
  }
};

// =============================================================================
// Language Metadata & State
// =============================================================================

const langMeta = {
  vi: { flag: "🇻🇳", label: "VI", title: "Tiếng Việt" },
  en: { flag: "🇺🇸", label: "EN", title: "English" },
  de: { flag: "🇩🇪", label: "DE", title: "Deutsch" },
  ja: { flag: "🇯🇵", label: "JA", title: "日本語" },
  "zh-TW": { flag: "🇹🇼", label: "繁中", title: "繁體中文" },
  "zh-CN": { flag: "🇨🇳", label: "简中", title: "简体中文" },
  fr: { flag: "🇫🇷", label: "FR", title: "Français" },
  es: { flag: "🇪🇸", label: "ES", title: "Español" },
  ar: { flag: "🇸🇦", label: "AR", title: "العربية" }
};

let currentLang = localStorage.getItem("notchpulse_lang");
if (!currentLang || !i18nData[currentLang]) {
  const browserLang = (navigator.language || "").toLowerCase();
  if (browserLang.startsWith("vi")) currentLang = "vi";
  else if (browserLang.startsWith("ja")) currentLang = "ja";
  else if (browserLang.startsWith("de")) currentLang = "de";
  else if (browserLang.startsWith("fr")) currentLang = "fr";
  else if (browserLang.startsWith("es")) currentLang = "es";
  else if (browserLang.startsWith("ar")) currentLang = "ar";
  else if (browserLang.startsWith("zh-tw") || browserLang.startsWith("zh-hk")) currentLang = "zh-TW";
  else if (browserLang.startsWith("zh")) currentLang = "zh-CN";
  else currentLang = "en";
}

let notchMode = "notch"; // 'notch' or 'island'
let currentAction = "faceid"; // 'faceid', 'music', 'battery', 'shelf'

// Permanent Dark Mode initialization
document.documentElement.setAttribute("data-theme", "dark");

document.addEventListener("DOMContentLoaded", () => {
  document.documentElement.setAttribute("data-theme", "dark");
  initNavbarScroll();
  initSmoothScroll();
  initReleaseAutoUpdater();
  initLanguage();
  initScrollFadeIn();
  initParallaxAndTilt();
  initNotchSimulator();
  initLaunchpadTabs();
  initReviewsFilter();
  initCopyActions();
});

// =============================================================================
// Smooth Navigation Links Scroll with Navbar Header Offset
// =============================================================================

function initSmoothScroll() {
  const prefersReduced = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.querySelectorAll('a[href^="#"], .nav-brand').forEach((anchor) => {
    anchor.addEventListener("click", function (e) {
      const href = this.getAttribute("href");
      const behavior = prefersReduced() ? "auto" : "smooth";

      if (!href || href === "#" || this.classList.contains("nav-brand")) {
        e.preventDefault();
        window.scrollTo({ top: 0, behavior });
        return;
      }

      const targetElement = document.querySelector(href);
      if (targetElement) {
        e.preventDefault();
        const headerOffset = href === "#main-content" ? 0 : 74;
        const elementPosition = targetElement.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

        window.scrollTo({
          top: offsetPosition,
          behavior
        });
        if (href === "#main-content") {
          targetElement.focus({ preventScroll: true });
        }
      }
    });
  });
}

// =============================================================================
// Launchpad Preview Accessible Tabs (Selection Follows Focus)
// =============================================================================

function initLaunchpadTabs() {
  const container = document.querySelector("[data-launchpad-tabs]");
  if (!container) return;

  const tabs = Array.from(container.querySelectorAll('[role="tab"]'));
  const panels = Array.from(container.querySelectorAll('[role="tabpanel"]'));
  if (!tabs.length || !panels.length) return;

  function selectTab(nextTab, moveFocus = false) {
    const targetPanelId = nextTab.getAttribute("data-lp-panel");
    tabs.forEach((tab) => {
      const isSelected = tab === nextTab;
      tab.setAttribute("aria-selected", isSelected ? "true" : "false");
      tab.setAttribute("tabindex", isSelected ? "0" : "-1");
    });

    panels.forEach((panel) => {
      panel.hidden = panel.id !== targetPanelId;
    });

    nextTab.scrollIntoView({ block: "nearest", inline: "nearest" });
    if (moveFocus) nextTab.focus();
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => selectTab(tab, false));

    tab.addEventListener("keydown", (e) => {
      let nextIndex = -1;
      if (e.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
      else if (e.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
      else if (e.key === "Home") nextIndex = 0;
      else if (e.key === "End") nextIndex = tabs.length - 1;

      if (nextIndex !== -1) {
        e.preventDefault();
        selectTab(tabs[nextIndex], true);
      }
    });
  });
}

// =============================================================================
// Dynamic Release Auto-Updater (Syncs latest version & DMG url from GitHub)
// =============================================================

let appReleaseInfo = {
  version: "v5.7",
  versionShort: "v5.7",
  name: "NotchPulse v5.7",
  downloadUrl: "https://github.com/HieuKunn/NotchPulse-Release-for-everyone/releases/latest/download/NotchPulse.dmg"
};

function initReleaseAutoUpdater() {
  try {
    sessionStorage.removeItem("notchpulse_latest_release");
  } catch (e) {}

  fetch(`https://api.github.com/repos/HieuKunn/NotchPulse-Release-for-everyone/releases/latest?_ts=${Date.now()}`, {
    cache: "no-store",
    headers: {
      "Accept": "application/vnd.github.v3+json"
    }
  })
    .then((res) => {
      if (!res.ok) throw new Error("GitHub API unavailable");
      return res.json();
    })
    .then((data) => {
      if (data && data.tag_name) {
        const rawTag = data.tag_name;
        const cleanVer = rawTag.startsWith("v") ? rawTag : "v" + rawTag;
        const shortVer = cleanVer;

        let dmgUrl = "https://github.com/HieuKunn/NotchPulse-Release-for-everyone/releases/latest/download/NotchPulse.dmg";
        if (data.assets && Array.isArray(data.assets)) {
          const dmgAsset = data.assets.find((a) => a.name && a.name.endsWith(".dmg"));
          if (dmgAsset && dmgAsset.browser_download_url) {
            dmgUrl = dmgAsset.browser_download_url;
          }
        }

        appReleaseInfo = {
          version: cleanVer,
          versionShort: shortVer,
          name: data.name || `NotchPulse ${shortVer}`,
          downloadUrl: dmgUrl
        };

        applyLanguage(currentLang);
        updateDownloadLinks(appReleaseInfo.downloadUrl);
      }
    })
    .catch(() => {
      // Graceful fallback to default v4.8.8
    });
}

function updateDownloadLinks(url) {
  if (!url) return;
  const links = document.querySelectorAll('a[href*="NotchPulse.dmg"]');
  links.forEach((link) => {
    link.href = url;
  });
}

// =============================================================================
// Navbar Scroll Transition (Transparent at Top, Frosted Coffee on Scroll)
// =============================================================================

function initNavbarScroll() {
  const navbar = document.getElementById("navbar");
  if (!navbar) return;

  let ticking = false;

  function updateNavbar() {
    if (window.scrollY > 15) {
      navbar.classList.add("scrolled");
    } else {
      navbar.classList.remove("scrolled");
    }
    ticking = false;
  }

  window.addEventListener("scroll", () => {
    if (!ticking) {
      window.requestAnimationFrame(updateNavbar);
      ticking = true;
    }
  }, { passive: true });

  // Initial state check
  updateNavbar();
}

// =============================================================================
// 1. Scroll-Driven Fade-In Animations (IntersectionObserver)
// =============================================================================

function initScrollFadeIn() {
  const elements = document.querySelectorAll(".fade-in-section");
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    });
  }, {
    threshold: 0.08,
    rootMargin: "0px 0px -40px 0px"
  });

  elements.forEach((el) => {
    observer.observe(el);
  });
}

// =============================================================================
// 2. Language Switcher (9 Languages: VI, EN, DE, JA, ZH-TW, ZH-CN, FR, ES, AR)
// =============================================================================

function initLanguage() {
  const wrapper = document.getElementById("langDropdownWrapper");
  const toggleBtn = document.getElementById("langToggle");
  const menu = document.getElementById("langMenu");

  // Apply initial language
  applyLanguage(currentLang);

  if (toggleBtn && wrapper) {
    toggleBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      const isOpen = wrapper.classList.toggle("open");
      toggleBtn.setAttribute("aria-expanded", isOpen ? "true" : "false");
    });

    // Close on click outside
    document.addEventListener("click", (e) => {
      if (!wrapper.contains(e.target)) {
        wrapper.classList.remove("open");
        toggleBtn.setAttribute("aria-expanded", "false");
      }
    });

    // Close on Escape key
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && wrapper.classList.contains("open")) {
        wrapper.classList.remove("open");
        toggleBtn.setAttribute("aria-expanded", "false");
        toggleBtn.focus();
      }
    });
  }

  if (menu) {
    menu.querySelectorAll(".lang-menu-item").forEach((btn) => {
      btn.addEventListener("click", () => {
        const lang = btn.getAttribute("data-lang");
        if (lang && i18nData[lang]) {
          currentLang = lang;
          localStorage.setItem("notchpulse_lang", lang);
          applyLanguage(lang);
          if (wrapper) {
            wrapper.classList.remove("open");
            if (toggleBtn) toggleBtn.setAttribute("aria-expanded", "false");
          }
        }
      });
    });
  }
}

function applyLanguage(lang) {
  const meta = langMeta[lang] || langMeta.en;
  const langLabel = document.getElementById("langLabel");
  const langFlag = document.getElementById("langFlag");

  if (langLabel) langLabel.textContent = meta.label;
  if (langFlag) langFlag.textContent = meta.flag;

  // Set HTML lang & text direction attributes for accessibility
  document.documentElement.setAttribute("lang", lang);
  document.documentElement.setAttribute("dir", lang === "ar" ? "rtl" : "ltr");

  // Update checkmarks in dropdown menu
  document.querySelectorAll(".lang-menu-item").forEach((btn) => {
    const isCurrent = btn.getAttribute("data-lang") === lang;
    btn.classList.toggle("active", isCurrent);
  });

  const dict = i18nData[lang] || i18nData.en;
  const enDict = i18nData.en;
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    let text = dict[key] || enDict[key];
    if (text) {
      text = text.replace(/\{version\}/g, appReleaseInfo.versionShort);
      text = text.replace(/\{fullVersion\}/g, appReleaseInfo.version);
      text = text.replace(/\{releaseName\}/g, appReleaseInfo.name);
      el.textContent = text;
    }
  });

  renderNotchContent();
}

// =============================================================================
// 3. 3D Mouse Perspective Tilt & Parallax
// =============================================================================

function initParallaxAndTilt() {
  const deviceFrame = document.getElementById("deviceFrame");
  const chips = document.querySelectorAll(".parallax-chip");
  const ambientGlow = document.getElementById("ambientGlow");

  if (!deviceFrame) return;

  window.addEventListener("mousemove", (e) => {
    const rect = deviceFrame.getBoundingClientRect();
    const frameCenterX = rect.left + rect.width / 2;
    const frameCenterY = rect.top + rect.height / 2;

    const deltaX = (e.clientX - frameCenterX) / (window.innerWidth / 2);
    const deltaY = (e.clientY - frameCenterY) / (window.innerHeight / 2);

    // Subtle, calm micro-tilt (-3.2deg to 3.2deg) to prevent excessive movement
    const rotX = Math.max(-3.2, Math.min(3.2, -deltaY * 3.6));
    const rotY = Math.max(-3.2, Math.min(3.2, deltaX * 3.6));

    deviceFrame.style.transform = `perspective(1400px) rotateX(${rotX}deg) rotateY(${rotY}deg)`;

    // Gentle micro-shift on floating outer chips
    chips.forEach((chip, idx) => {
      const dir = idx % 2 === 0 ? -1 : 1;
      chip.style.transform = `translate3d(${rotY * dir * 1.5}px, ${rotX * dir * 1.5}px, 25px)`;
    });
  });

  window.addEventListener("mouseleave", () => {
    deviceFrame.style.transform = "perspective(1400px) rotateX(0deg) rotateY(0deg)";
    chips.forEach((chip) => {
      chip.style.transform = "translate3d(0, 0, 0)";
    });
  });
}

// =============================================================================
// 4. Interactive MacBook Notch & Dynamic Island Simulator
// =============================================================================

function initNotchSimulator() {
  const notch = document.getElementById("notchElement");
  const btnNotch = document.getElementById("btnModeNotch");
  const btnIsland = document.getElementById("btnModeIsland");

  const pillFaceID = document.getElementById("pillFaceID");
  const pillMusic = document.getElementById("pillMusic");
  const pillBattery = document.getElementById("pillBattery");
  const pillShelf = document.getElementById("pillShelf");

  if (btnNotch && btnIsland) {
    btnNotch.addEventListener("click", () => {
      notchMode = "notch";
      btnNotch.classList.add("active");
      btnIsland.classList.remove("active");
      notch.classList.remove("dynamic-island");
    });

    btnIsland.addEventListener("click", () => {
      notchMode = "island";
      btnIsland.classList.add("active");
      btnNotch.classList.remove("active");
      notch.classList.add("dynamic-island");
    });
  }

  const actionPills = [
    { el: pillFaceID, action: "faceid" },
    { el: pillMusic, action: "music" },
    { el: pillBattery, action: "battery" },
    { el: pillShelf, action: "shelf" }
  ];

  let isPinned = false;

  actionPills.forEach(({ el, action }) => {
    if (el) {
      el.addEventListener("click", () => {
        actionPills.forEach((p) => p.el.classList.remove("active"));
        el.classList.add("active");
        currentAction = action;
        isPinned = true;
        notch.classList.add("expanded");
        renderNotchContent(true);
      });
    }
  });

  if (notch) {
    notch.addEventListener("mouseenter", () => {
      notch.classList.add("expanded");
      renderNotchContent();
    });

    notch.addEventListener("mouseleave", () => {
      if (!isPinned) {
        notch.classList.remove("expanded");
      }
    });

    notch.addEventListener("click", () => {
      isPinned = !isPinned;
      if (isPinned) {
        notch.classList.add("expanded");
      } else {
        notch.classList.remove("expanded");
      }
      renderNotchContent();
    });
  }
}

let lastRenderedState = "";

function renderNotchContent(force = false) {
  const content = document.getElementById("notchExpandedContent");
  const compactIcon = document.getElementById("compactIcon");
  const compactText = document.getElementById("compactText");
  const dict = i18nData[currentLang] || i18nData.en;

  if (!content) return;

  const currentStateKey = currentAction + "_" + currentLang;
  if (!force && lastRenderedState === currentStateKey) {
    return;
  }
  lastRenderedState = currentStateKey;

  if (currentAction === "faceid") {
    if (compactIcon) compactIcon.textContent = "👤";
    if (compactText) compactText.textContent = dict["notch.faceIdScanned"] || "Face ID Verified";

    content.innerHTML = `
      <div class="faceid-scanner-anim">
        <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M8 3H5a2 2 0 0 0-2 2v3m0 8v3a2 2 0 0 0 2 2h3m8 0h3a2 2 0 0 0 2-2v-3m0-8V5a2 2 0 0 0-2-2h-3"/>
          <circle cx="9" cy="9" r="1.2" fill="currentColor"/>
          <circle cx="15" cy="9" r="1.2" fill="currentColor"/>
          <path d="M12 11v2"/>
          <path d="M8.5 15.5c1.8 1.8 5.2 1.8 7 0"/>
        </svg>
      </div>
      <div style="font-weight: 700; font-size: 1.05rem; color: #fff;">
        ${dict["notch.faceIdScanned"] || "Face ID Verified"}
      </div>
      <div style="font-size: 0.8rem; color: #d9cbbe; margin-top: 4px;">
        ${dict["notch.faceIdPrompt"] || "Apple Vision on-device biometric check"}
      </div>
    `;
  } else if (currentAction === "music") {
    if (compactIcon) compactIcon.textContent = "🎵";
    if (compactText) compactText.textContent = "STAY • Justin Bieber";

    content.innerHTML = `
      <div style="display: flex; align-items: center; gap: 14px; width: 100%; max-width: 320px; justify-content: center; margin-bottom: 12px;">
        <div style="width: 46px; height: 46px; border-radius: 10px; background: linear-gradient(135deg, #ec4899, #8b5cf6); display: flex; align-items: center; justify-content: center; font-size: 1.4rem;">🎶</div>
        <div style="text-align: left;">
          <div style="font-weight: 700; font-size: 0.95rem; color: #fff;">Stay (Live Synced)</div>
          <div style="font-size: 0.78rem; color: #94a3b8;">The Kid LAROI, Justin Bieber</div>
        </div>
      </div>
      <div style="font-size: 0.88rem; font-weight: 500; color: #FFFFFF; background: rgba(255, 255, 255, 0.08); padding: 6px 14px; border-radius: 9999px; border: 1px solid rgba(255, 255, 255, 0.15);">
        ${dict["bento.songLyrics"] || '"Drifting through the calm, soundscapes in the night..."'}
      </div>
    `;
  } else if (currentAction === "battery") {
    if (compactIcon) compactIcon.textContent = "⚡️";
    if (compactText) compactText.textContent = "86% • 98W MagSafe";

    content.innerHTML = `
      <div style="font-size: 2.2rem; color: #22c55e; margin-bottom: 4px;">⚡️</div>
      <div style="font-weight: 700; font-size: 1.1rem; color: #fff;">
        86% — 98W Fast Charging
      </div>
      <div style="font-size: 0.8rem; color: #94a3b8; margin-top: 4px;">
        ${dict["notch.batteryPrompt"] || "Full in 18 minutes • Battery Health: 100%"}
      </div>
    `;
  } else if (currentAction === "shelf") {
    if (compactIcon) compactIcon.textContent = "📁";
    if (compactText) compactText.textContent = dict["notch.shelfItems"] || "Shelf: 3 Items";

    content.innerHTML = `
      <div style="display: flex; gap: 8px; width: 100%; margin-bottom: 6px;">
        <div style="width: 74px; height: 64px; border-radius: 12px; border: 1.5px dashed rgba(255, 235, 220, 0.2); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; background: rgba(255, 255, 255, 0.03);">
          <div style="width: 28px; height: 28px; border-radius: 50%; background: rgba(255, 255, 255, 0.08); display: flex; align-items: center; justify-content: center;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>
          </div>
          <span style="font-size: 0.65rem; font-weight: 600; color: #fff;">AirDrop</span>
        </div>
        <div style="flex: 1; height: 64px; border-radius: 12px; border: 1.5px dashed rgba(255, 235, 220, 0.2); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; background: rgba(255, 255, 255, 0.03); position: relative;">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><polyline points="7 10 12 15 17 10"/><line x1="12" y1="3" x2="12" y2="15"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/></svg>
          <span style="font-size: 0.72rem; font-weight: 500; color: #C8BAAF;">${dict["shelf.dropText"] || "Drop files here"}</span>
        </div>
      </div>
      <div style="font-size: 0.76rem; color: #94a3b8;">
        ${dict["notch.shelfPrompt"] || "Drop files into notch to stash temporarily"}
      </div>
    `;
  }
}

// =============================================================================
// 5. Testimonial Rating Filter (All, 5, 4.5, 4, 3.5)
// =============================================================================

function initReviewsFilter() {
  const filterBtns = document.querySelectorAll(".filter-btn");
  const allCards = Array.from(document.querySelectorAll(".testimonial-card"));

  function applyFilter(filterValue) {
    const visibleCardsSet = new Set();

    if (filterValue === "all") {
      // Pick 6 random cards out of all cards for a compact, fresh layout
      const shuffled = [...allCards].sort(() => 0.5 - Math.random());
      shuffled.slice(0, 6).forEach((card) => visibleCardsSet.add(card));
    } else {
      allCards.forEach((card) => {
        if (card.getAttribute("data-rating") === filterValue) {
          visibleCardsSet.add(card);
        }
      });
    }

    allCards.forEach((card) => {
      if (visibleCardsSet.has(card)) {
        card.style.display = "flex";
        setTimeout(() => {
          card.style.opacity = "1";
          card.style.transform = "translateY(0)";
        }, 50);
      } else {
        card.style.display = "none";
        card.style.opacity = "0";
        card.style.transform = "translateY(20px)";
      }
    });
  }

  filterBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      filterBtns.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      const filterValue = btn.getAttribute("data-filter");
      applyFilter(filterValue);
    });
  });

  // Initial load: display 6 random cards for 'All'
  applyFilter("all");
}

// =============================================================================
// 6. Homebrew Copy Command & Toast Notification
// =============================================================================

function initCopyActions() {
  const copyBoxes = [document.getElementById("copyBrewCmd"), document.getElementById("copyBrewCmdFooter")];
  const toast = document.getElementById("copyToast");
  const brewCommand = "brew install --cask https://raw.githubusercontent.com/HieuKunn/NotchPulse-Release-for-everyone/main/Casks/notchpulse.rb";

  copyBoxes.forEach((box) => {
    if (box) {
      box.addEventListener("click", () => {
        navigator.clipboard.writeText(brewCommand).then(() => {
          showToast();
        }).catch(() => {
          showToast();
        });
      });
    }
  });

  function showToast() {
    if (!toast) return;
    toast.classList.add("show");
    setTimeout(() => {
      toast.classList.remove("show");
    }, 2800);
  }
}
