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
// Localization Dictionary (EN / VI / DE / JA / ZH-TW / ZH-CN / ES)
// =============================================================================

const i18nData = {
  en: {
    // Navigation
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
    "hero.subtitle": "Transform your MacBook camera notch into a fluid, 120Hz ProMotion interactive Dynamic Island. Native Apple Silicon performance with Biometric Face ID, real-time lyrics, and smart hardware HUDs.",
    "hero.downloadBtn": "Download NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Verified",
    "chip.faceidSub": "On-Device Neural Engine",
    "chip.ddcTitle": "DDC Display Control",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Active",
    "chip.batterySub": "Smart 80% Limit Protected",
    "chip.shelfTitle": "Notch Shelf Ready",
    "chip.shelfSub": "Drag & Drop to Hold Files",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU Idle Overhead",
    "chip.lyricsTitle": "Live Synced Lyrics",
    "chip.lyricsSub": "Spotify & Apple Music",

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
    "features.subtitle": "Built natively in Swift with 0% CPU overhead at idle. Experience smooth 120Hz ProMotion animations, biometric conveniences, and smart desktop tools.",
    
    "feat1.title": "Biometric Face ID Recognition",
    "feat1.desc": "Brings iOS-grade facial recognition to your Mac. Continuously senses your presence, previews camera status smoothly, and unlocks protected apps with privacy-first on-device Apple Vision processing.",
    "bento.faceidVerified": "Neural Face Mesh Active",
    "bento.faceidSub": "512D Vector Embedding • On-Device Apple Vision",
    "bento.faceidHandshake": "Lock Screen to Active Desktop Zero-Lag Handshake",

    "feat2.title": "120Hz ProMotion Dual Mode",
    "feat2.desc": "Fluidly morphs between native MacBook Notch profile and a centered floating Dynamic Island on external Studio Displays.",
    "bento.springPhysics": "Spring Physics (response: 0.38s)",

    "feat3.title": "Live Synced Lyrics",
    "feat3.desc": "Live word-by-word streaming lyrics for Spotify and Apple Music directly over the notch. Scrub tracks, seek timestamps, or expand into fullscreen lyric mode with vibrant album artwork.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf & Quick Drop",
    "feat4.desc": "Drag files, links, or screenshots directly into the notch bezel to hold them temporarily across workspaces and apps.",
    "shelf.dropText": "Drop files here",

    "feat5.title": "Hardware DDC External Display HUD",
    "feat5.desc": "Control genuine third-party monitor hardware brightness and audio volume via DDC/CI with native Apple keyboard shortcuts.",
    "bento.ddcBrightness": "Dell UltraSharp 4K Brightness",
    "bento.ddcVolume": "Built-in Audio Volume",

    "feat6.title": "Live CPU, RAM & GPU System Monitor",
    "feat6.desc": "Real-time hardware telemetry directly inside the notch. Track Apple Silicon unified memory pressure, CPU core clusters, and GPU load with 0% idle overhead.",
    "bento.cpuCores": "8 Cores Active",
    "bento.ramUsage": "10.3 / 16 GB Active",
    "bento.gpuFps": "120 FPS Metal Pro",

    // Reviews Section
    "reviews.tag": "Global Community",
    "reviews.title": "Loved by Developers Worldwide",
    "reviews.subtitle": "Real feedback from Mac engineers, designers, and creators across the globe with diverse ratings.",
    "reviews.all": "All Reviews (4.8 ★)",
    "reviews.five": "5 Stars",
    "reviews.fourPointFive": "4.5 Stars",
    "reviews.four": "4 Stars",
    "reviews.threePointFive": "3.5 Stars",

    // Creator Section
    "creator.tag": "Meet The Creator",
    "creator.bio": "ITM student with a deep passion for system design and native macOS architectures. Built NotchPulse from scratch to explore human-computer interaction and make the MacBook notch genuinely delightful and functional.",

    // Installation Section
    "install.tag": "Ready to Elevate Your Mac?",
    "install.title": "Get NotchPulse Today",
    "install.subtitle": "Compatible with macOS 14.0+ Sonoma and macOS 15 Sequoia. Optimized for all Mac devices (Apple Silicon & Intel Macs).",
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
    "nav.features": "Tính Năng Bento",
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
    "hero.subtitle": "Biến phần khuyết camera trên MacBook thành Dynamic Island tương tác mượt mà 120Hz ProMotion. Tối ưu hoàn hảo cho chip Apple Silicon với nhận diện Face ID, lời bài hát đồng bộ thời gian thực và bảng điều khiển HUD thông minh.",
    "hero.downloadBtn": "Tải Trực Tiếp NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Sẵn Sàng",
    "chip.faceidSub": "Nhận diện khuôn mặt Neural Engine",
    "chip.ddcTitle": "Điều Khiển Màn Hình DDC",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "Sạc MagSafe 98W",
    "chip.batterySub": "Bảo vệ pin thông minh 80%",
    "chip.shelfTitle": "Notch Shelf Sẵn Sàng",
    "chip.shelfSub": "Kéo thả để lưu trữ tệp",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU khi chạy nền",
    "chip.lyricsTitle": "Lời Nhạc Trực Tiếp",
    "chip.lyricsSub": "Spotify & Apple Music",

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
    "features.subtitle": "Viết bằng Swift thuần túy, 0% CPU khi chạy nền. Tận hưởng hoạt ảnh 120Hz ProMotion, bảo mật sinh trắc học và công cụ làm việc thông minh.",
    
    "feat1.title": "Mở Khoá Face ID Sinh Trắc Học",
    "feat1.desc": "Mang trải nghiệm nhận diện khuôn mặt chuẩn iPhone lên máy Mac. Tự động cảm biến hiện diện, xem trước camera mượt mà và mở khóa ứng dụng an toàn với Apple Vision ngay trên thiết bị.",
    "bento.faceidVerified": "Mô Hình Lưới Face Mesh Kích Hoạt",
    "bento.faceidSub": "Véc-tơ 512D • Apple Vision trên thiết bị",
    "bento.faceidHandshake": "Mở khoá tức thì không độ trễ từ Màn hình khoá",

    "feat2.title": "Chế Độ Kép 120Hz Notch & Island",
    "feat2.desc": "Tự động chuyển đổi linh hoạt giữa màn hình tai thỏ MacBook Pro và màn hình ngoài Studio Display ở tần số 120Hz ProMotion.",
    "bento.springPhysics": "Vật lý lò xo Apple (độ trễ: 0.38s)",

    "feat3.title": "Lời Bài Hát Đồng Bộ Trực Tiếp",
    "feat3.desc": "Hiển thị lời bài hát đồng bộ chạy từng chữ theo thời gian thực trên tai thỏ cho Spotify và Apple Music. Rê chuột để tua nhạc, tạm dừng hoặc xem ảnh bìa album siêu nét.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Ngăn Kéo Notch Shelf & Thả Nhanh",
    "feat4.desc": "Biến phần khuyết tai thỏ thành nơi lưu tạm tài liệu thông minh. Kéo thả file, ảnh, đường link hoặc đoạn mã lên đỉnh màn hình để chuyển đổi nhanh giữa các app.",
    "shelf.dropText": "Thả tệp vào đây",

    "feat5.title": "Điều Khiển Màn Hình Ngoài DDC HUD",
    "feat5.desc": "Can thiệp phần cứng DDC/CI trực tiếp cho màn hình rời. Tăng giảm độ sáng thật, độ tương phản và âm lượng bằng phím tắt bàn phím tiện lợi.",
    "bento.ddcBrightness": "Độ sáng màn hình Dell UltraSharp 4K",
    "bento.ddcVolume": "Âm lượng loa tích hợp",

    "feat6.title": "Giám Sát Phần Cứng CPU, RAM & GPU",
    "feat6.desc": "Theo dõi hiệu năng phần cứng theo thời gian thực ngay trên tai thỏ. Kiểm soát dung lượng RAM Hợp nhất, xung nhịp CPU và tải GPU mà không tốn CPU lúc chạy nền.",
    "bento.cpuCores": "8 Nhân Đang Hoạt Động",
    "bento.ramUsage": "10.3 / 16 GB Đang Dùng",
    "bento.gpuFps": "120 FPS Metal Pro",

    // Reviews Section
    "reviews.tag": "Cộng Đồng Toàn Cầu",
    "reviews.title": "Được Kỹ Sư Toàn Cầu Đánh Giá Cao",
    "reviews.subtitle": "Phản hồi thực tế từ các lập trình viên, nhà thiết kế UI/UX trên khắp thế giới với các mức đánh giá phong phú.",
    "reviews.all": "Tất Cả Đánh Giá (4.8 ★)",
    "reviews.five": "5 Sao",
    "reviews.fourPointFive": "4.5 Sao",
    "reviews.four": "4 Sao",
    "reviews.threePointFive": "3.5 Sao",

    // Creator Section
    "creator.tag": "Gặp Gỡ Tác Giả",
    "creator.bio": "Sinh viên ITM đam mê System Design và kiến trúc hệ thống native trên macOS. Xây dựng NotchPulse từ số 0 để học hỏi, trải nghiệm tương tác người - máy và biến tai thỏ MacBook thành một không gian tiện ích thú vị.",

    // Installation Section
    "install.tag": "Sẵn Sàng Nâng Cấp Máy Mac Của Bạn?",
    "install.title": "Cài Đặt NotchPulse Ngay Hôm Nay",
    "install.subtitle": "Tương thích hoàn toàn với macOS 14.0+ Sonoma và macOS 15 Sequoia. Tối ưu hóa cho toàn bộ các dòng máy Mac (Apple Silicon & Intel).",
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
    "hero.subtitle": "Verwandle die MacBook-Kamerakerbe in eine flüssige 120Hz ProMotion Dynamic Island. Native Apple Silicon Performance mit Face ID, synchronisierten Songtexten und Hardware-HUDs.",
    "hero.downloadBtn": "NotchPulse.dmg herunterladen ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Bestätigt",
    "chip.faceidSub": "On-Device Neural Engine",
    "chip.ddcTitle": "DDC Display-Steuerung",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Aktiv",
    "chip.batterySub": "Intelligenter 80% Ladeschutz",
    "chip.shelfTitle": "Notch-Ablage Bereit",
    "chip.shelfSub": "Dateien schnell ablegen",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% CPU-Last im Leerlauf",
    "chip.lyricsTitle": "Live-Songtexte",
    "chip.lyricsSub": "Spotify & Apple Music",

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
    "features.subtitle": "Nativ in Swift entwickelt mit 0% CPU-Last im Leerlauf. Erlebe butterweiche 120Hz ProMotion Animationen und smarte Desktop-Werkzeuge.",
    
    "feat1.title": "Biometrische Face ID Erkennung",
    "feat1.desc": "Bringt iOS-Gesichtserkennung auf deinen Mac. Kontinuierliche Anwesenheitserkennung und sicheres Entsperren mit Apple Vision direkt auf dem Gerät.",
    "bento.faceidVerified": "Neural Face Mesh Aktiv",
    "bento.faceidSub": "512D Vektor-Embedding • On-Device Apple Vision",
    "bento.faceidHandshake": "Sperrbildschirm-zu-Desktop Handshake ohne Verzögerung",

    "feat2.title": "120Hz ProMotion Dual-Modus",
    "feat2.desc": "Wechselt flüssig zwischen nativer MacBook Notch und zentrierter Dynamic Island auf externen Bildschirmen.",
    "bento.springPhysics": "Apple Federphysik (Reaktion: 0.38s)",

    "feat3.title": "Synchronisierte Live-Songtexte",
    "feat3.desc": "Wortgenaue Songtexte für Spotify und Apple Music direkt an der Notch. Musik steuern und Cover-Artworks in Vollbild genießen.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf & Schnelles Ablegen",
    "feat4.desc": "Dateien, Links oder Bildschirmfotos direkt in die Notch ziehen, um sie zwischen Schreibtischen und Apps bereitzuhalten.",
    "shelf.dropText": "Dateien hier ablegen",

    "feat5.title": "Hardware DDC Display-Steuerung",
    "feat5.desc": "Echte Hardware-Helligkeit und Lautstärke externer Monitore über DDC/CI mit Apple-Tastaturkurzbefehlen steuern.",
    "bento.ddcBrightness": "Dell UltraSharp 4K Helligkeit",
    "bento.ddcVolume": "Integrierte Lautstärke",

    "feat6.title": "Echtzeit CPU, RAM & GPU Monitor",
    "feat6.desc": "Hardware-Telemetrie direkt in der Notch. Apple Silicon Speicherdruck, CPU-Cluster und GPU-Last mit 0% Leerlauf-Overhead überwachen.",
    "bento.cpuCores": "8 Kerne Aktiv",
    "bento.ramUsage": "10.3 / 16 GB Aktiv",
    "bento.gpuFps": "120 FPS Metal Pro",

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
    "install.subtitle": "Kompatibel mit macOS 14.0+ Sonoma und macOS 15 Sequoia. Optimiert für alle Mac-Geräte (Apple Silicon & Intel).",
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
    "hero.subtitle": "MacBookのカメラノッチを滑らかな120Hz ProMotionのDynamic Islandへ進化。Face ID生体認証、リアルタイム同期歌詞、スマートハードウェアHUDを搭載。",
    "hero.downloadBtn": "NotchPulse.dmg をダウンロード ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 認証完了",
    "chip.faceidSub": "デバイス内 Neural Engine",
    "chip.ddcTitle": "DDC ディスプレイ制御",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 稼働中",
    "chip.batterySub": "スマート80%充電保護",
    "chip.shelfTitle": "ノッチシェルフ対応",
    "chip.shelfSub": "ドラッグ＆ドロップで一時保存",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "アイドル時CPU負荷 0%",
    "chip.lyricsTitle": "リアルタイム同期歌詞",
    "chip.lyricsSub": "Spotify & Apple Music 対応",

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
    "features.subtitle": "Swiftネイティブ開発、アイドル時CPU消費0%。120Hzの超滑らかなProMotionアニメーションと洗練された機能群。",
    
    "feat1.title": "生体認証 Face ID 顔認識",
    "feat1.desc": "iPhone品質の顔認識をMacへ。Apple Visionによるデバイス内処理で、プライバシーを守りながら安全にロック解除。",
    "bento.faceidVerified": "Neural Face Mesh 稼働中",
    "bento.faceidSub": "512D ベクトル埋め込み • デバイス内 Apple Vision",
    "bento.faceidHandshake": "ロック画面からデスクトップへ遅延ゼロの連携",

    "feat2.title": "120Hz ProMotion デュアルモード",
    "feat2.desc": "MacBookの内蔵ノッチと外部ディスプレイ上のDynamic Islandをシームレスに切り替え。",
    "bento.springPhysics": "Apple スプリング物理演算 (応答: 0.38s)",

    "feat3.title": "リアルタイム同期歌詞表示",
    "feat3.desc": "SpotifyやApple Musicとリアルタイムに同期し、ノッチ上に歌詞を一語ずつ表示。トラック操作も手軽に。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "ノッチシェルフ & クイックドロップ",
    "feat4.desc": "ファイル、リンク、スクリーンショットをノッチに直接ドラッグして、アプリやワークスペース間で一時保存。",
    "shelf.dropText": "ここにファイルをドロップ",

    "feat5.title": "外部モニター DDC ハードウェア制御",
    "feat5.desc": "DDC/CIプロトコル経由で外部モニター本来の輝度や音量をApple標準ショートカットで直接調整。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 輝度",
    "bento.ddcVolume": "内蔵オーディオ音量",

    "feat6.title": "CPU・RAM・GPU リアルタイム監視",
    "feat6.desc": "Apple Siliconのメモリプレッシャー、CPUコア稼働率、GPU負荷をノッチ上で常時把握。",
    "bento.cpuCores": "8コア 稼働中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

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
    "install.subtitle": "macOS 14.0+ Sonoma および macOS 15 Sequoia 対応。すべてのMac（Apple Silicon & Intel）に最適化。",
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
    "hero.subtitle": "將 MacBook 鏡頭瀏海蛻變為流暢的 120Hz ProMotion 靈動島。原生 Apple Silicon 極致效能，具備 Face ID 辨識、即時同步歌詞與硬體監控儀表板。",
    "hero.downloadBtn": "下載 NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 認證成功",
    "chip.faceidSub": "本機端 Neural Engine",
    "chip.ddcTitle": "DDC 螢幕硬體控制",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 充能中",
    "chip.batterySub": "智慧 80% 充電保護",
    "chip.shelfTitle": "瀏海暫存區已就緒",
    "chip.shelfSub": "拖放即可暫存檔案",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "待機時 0% CPU 佔用",
    "chip.lyricsTitle": "即時同步歌詞",
    "chip.lyricsSub": "支援 Spotify 與 Apple Music",

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
    "features.subtitle": "以 Swift 原生開發，待機 0% CPU 負荷。享受流暢 120Hz ProMotion 動效、生物特徵辨識與智慧桌面工具。",
    
    "feat1.title": "生物特徵 Face ID 臉部辨識",
    "feat1.desc": "將 iOS 等級的臉部辨識帶入 Mac。持續感應使用者在位狀態，並透過 Apple Vision 於本機端安全完成辨識與解鎖。",
    "bento.faceidVerified": "類神經網格 Face Mesh 運算中",
    "bento.faceidSub": "512D 向量嵌入 • 本機端 Apple Vision",
    "bento.faceidHandshake": "鎖定畫面至桌面零延遲即時切換",

    "feat2.title": "120Hz ProMotion 雙形態模式",
    "feat2.desc": "在 MacBook 內建瀏海與外接螢幕置中靈動島之間自然變換形態。",
    "bento.springPhysics": "Apple 彈簧物理引擎 (響應: 0.38s)",

    "feat3.title": "即時滾動同步歌詞",
    "feat3.desc": "精準逐字顯示 Spotify 與 Apple Music 歌詞於瀏海上方，支援快速拖動進度與全螢幕專輯封面展示。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "瀏海暫存區 Notch Shelf",
    "feat4.desc": "將檔案、截圖或連結拖曳至螢幕邊緣暫存，輕鬆穿梭跨桌面與各項工作流程。",
    "shelf.dropText": "將檔案拖曳至此",

    "feat5.title": "硬體級 DDC 外接螢幕控制",
    "feat5.desc": "透過 DDC/CI 協定直接調整第三方螢幕的真實亮度與硬體音量，相容 Apple 原生快捷鍵。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 亮度",
    "bento.ddcVolume": "內建喇叭音量",

    "feat6.title": "即時 CPU、RAM 與 GPU 系統監控",
    "feat6.desc": "於瀏海即時掌握硬體資訊：Apple Silicon 統一記憶體壓力、CPU 核心頻率與 GPU 負載，零待機損耗。",
    "bento.cpuCores": "8 核心運作中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

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
    "install.subtitle": "相容於 macOS 14.0+ Sonoma 與 macOS 15 Sequoia。專為所有 Mac 機型（Apple Silicon 與 Intel）深度優化。",
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
    "hero.subtitle": "将 MacBook 摄像头刘海变为丝滑流畅的 120Hz ProMotion 灵动岛。基于 Apple Silicon 原生性能，支持 Face ID 识别、实时同步歌词与硬件监控 HUD。",
    "hero.downloadBtn": "下载 NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID 验证成功",
    "chip.faceidSub": "端侧 Neural Engine",
    "chip.ddcTitle": "DDC 硬件显示控制",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe 快充中",
    "chip.batterySub": "智能 80% 充电保护",
    "chip.shelfTitle": "刘海暂存架已就绪",
    "chip.shelfSub": "拖拽即时暂存文件",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "待机 0% CPU 占用",
    "chip.lyricsTitle": "实时同步歌词",
    "chip.lyricsSub": "支持 Spotify 与 Apple Music",

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
    "features.subtitle": "采用 Swift 纯原生编写，待机状态 0% CPU 占用。尽享 120Hz ProMotion 动画、生物识别与高能桌面工具。",
    
    "feat1.title": "生物识别 Face ID 人脸解锁",
    "feat1.desc": "将 iOS 级人脸识别带入 Mac。持续感应在位状态，依靠端侧 Apple Vision 算法保障隐私，安全快速解锁应用。",
    "bento.faceidVerified": "神经网格 Face Mesh 运算中",
    "bento.faceidSub": "512D 向量嵌入 • 端侧 Apple Vision",
    "bento.faceidHandshake": "锁定屏幕至桌面零延迟极速切换",

    "feat2.title": "120Hz ProMotion 双形态切换",
    "feat2.desc": "在 MacBook 自带刘海与外接 Studio Display 显示器的居中灵动岛之间顺畅自如地切换。",
    "bento.springPhysics": "Apple 弹簧物理引擎 (响应: 0.38s)",

    "feat3.title": "实时滚动同步歌词",
    "feat3.desc": "逐词同步播放 Spotify 与 Apple Music 歌词。随时在刘海处拖拽进度、暂停播放或展开专辑封面。",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "刘海暂存架 Notch Shelf",
    "feat4.desc": "将文件、链接或截图直接拖拽至刘海边缘暂存，在各工作区与多任务间便捷流转。",
    "shelf.dropText": "拖拽文件到这里",

    "feat5.title": "DDC 协议外接显示器硬件控制",
    "feat5.desc": "通过 DDC/CI 协议直接调节外接显示器的原生硬件亮度与音量，完美适配 Apple 键盘快捷键。",
    "bento.ddcBrightness": "Dell UltraSharp 4K 亮度",
    "bento.ddcVolume": "内置扬声器音量",

    "feat6.title": "实时 CPU、RAM 与 GPU 监控",
    "feat6.desc": "在刘海直观掌握统一内存压力、CPU 核心频率与 GPU 占用，零待机性能损耗。",
    "bento.cpuCores": "8 核心运行中",
    "bento.ramUsage": "10.3 / 16 GB 使用中",
    "bento.gpuFps": "120 FPS Metal Pro",

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
    "install.subtitle": "兼容 macOS 14.0+ Sonoma 与 macOS 15 Sequoia。针对所有 Mac 设备（Apple Silicon 与 Intel）深度优化。",
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
    "hero.subtitle": "Transforma el notch de tu MacBook en una Dynamic Island interactiva y fluida a 120Hz ProMotion. Rendimiento nativo en Apple Silicon con Face ID, letras en tiempo real y paneles HUD inteligentes.",
    "hero.downloadBtn": "Descargar NotchPulse.dmg ({version})",
    "hero.notchSong": "Midnight Pulse — Lofi Waves",

    // Chips
    "chip.faceidTitle": "Face ID Verificado",
    "chip.faceidSub": "Neural Engine en el Dispositivo",
    "chip.ddcTitle": "Control DDC de Pantallas",
    "chip.ddcSub": "Dell UltraSharp 4K • 82%",
    "chip.batteryTitle": "98W MagSafe Activo",
    "chip.batterySub": "Protección inteligente al 80%",
    "chip.shelfTitle": "Notch Shelf Listo",
    "chip.shelfSub": "Arrastra y suelta archivos",
    "chip.fpsTitle": "120Hz ProMotion",
    "chip.fpsSub": "0% de CPU en reposo",
    "chip.lyricsTitle": "Letras Sincronizadas",
    "chip.lyricsSub": "Spotify y Apple Music",

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
    "features.subtitle": "Creado nativamente en Swift con 0% de uso de CPU en reposo. Animaciones fluidas ProMotion a 120Hz, seguridad biométrica y herramientas inteligentes.",
    
    "feat1.title": "Reconocimiento Facial Face ID",
    "feat1.desc": "Lleva el desbloqueo facial estilo iOS a tu Mac. Detección continua de presencia y desbloqueo seguro con Apple Vision en el propio dispositivo.",
    "bento.faceidVerified": "Malla Facial Neuronal Activa",
    "bento.faceidSub": "Incrustación vectorial 512D • Apple Vision en el dispositivo",
    "bento.faceidHandshake": "Transición sin retardo de pantalla de bloqueo a escritorio",

    "feat2.title": "Modo Dual 120Hz Notch & Isla",
    "feat2.desc": "Cambia con total fluidez entre el notch integrado de la MacBook y una Dynamic Island centrada en monitores externos.",
    "bento.springPhysics": "Física de resortes de Apple (respuesta: 0.38s)",

    "feat3.title": "Letras Sincronizadas en Vivo",
    "feat3.desc": "Letras palabra por palabra en tiempo real para Spotify y Apple Music sobre el notch. Controla canciones y disfruta del arte del álbum.",
    "bento.songLyrics": "\"Drifting through the calm, soundscapes in the night...\"",

    "feat4.title": "Notch Shelf y Arrastre Rápido",
    "feat4.desc": "Arrastra archivos, enlaces o capturas directamente a la muesca del notch para guardarlos temporalmente entre espacios.",
    "shelf.dropText": "Suelta los archivos aquí",

    "feat5.title": "Control de Monitores Externos DDC",
    "feat5.desc": "Controla el brillo real y volumen por hardware de monitores de terceros mediante DDC/CI con los atajos de teclado de Apple.",
    "bento.ddcBrightness": "Brillo Dell UltraSharp 4K",
    "bento.ddcVolume": "Volumen de Audio Integrado",

    "feat6.title": "Monitor de Sistema CPU, RAM y GPU",
    "feat6.desc": "Telemetría de hardware en tiempo real en el notch: presión de memoria unificada, núcleos de CPU y carga de GPU sin consumo en reposo.",
    "bento.cpuCores": "8 Núcleos Activos",
    "bento.ramUsage": "10.3 / 16 GB Activo",
    "bento.gpuFps": "120 FPS Metal Pro",

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
    "install.subtitle": "Compatible con macOS 14.0+ Sonoma y macOS 15 Sequoia. Optimizado para todos los modelos de Mac (Apple Silicon e Intel).",
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
  es: { flag: "🇪🇸", label: "ES", title: "Español" }
};

let currentLang = localStorage.getItem("notchpulse_lang");
if (!currentLang || !i18nData[currentLang]) {
  const browserLang = (navigator.language || "").toLowerCase();
  if (browserLang.startsWith("vi")) currentLang = "vi";
  else if (browserLang.startsWith("ja")) currentLang = "ja";
  else if (browserLang.startsWith("de")) currentLang = "de";
  else if (browserLang.startsWith("es")) currentLang = "es";
  else if (browserLang.startsWith("zh-tw") || browserLang.startsWith("zh-hk")) currentLang = "zh-TW";
  else if (browserLang.startsWith("zh")) currentLang = "zh-CN";
  else if (browserLang.startsWith("en")) currentLang = "en";
  else currentLang = "vi";
}

let notchMode = "notch"; // 'notch' or 'island'
let currentAction = "faceid"; // 'faceid', 'music', 'battery', 'shelf'

// Permanent Dark Mode initialization
document.documentElement.setAttribute("data-theme", "dark");

document.addEventListener("DOMContentLoaded", () => {
  document.documentElement.setAttribute("data-theme", "dark");
  initNavbarScroll();
  initReleaseAutoUpdater();
  initLanguage();
  initScrollFadeIn();
  initParallaxAndTilt();
  initNotchSimulator();
  initReviewsFilter();
  initCopyActions();
});

// =============================================================================
// Dynamic Release Auto-Updater (Syncs latest version & DMG url from GitHub)
// =============================================================

let appReleaseInfo = {
  version: "v4.6.1",
  versionShort: "v4.6.1",
  name: "NotchPulse v4.6.1",
  downloadUrl: "https://github.com/HieuKunn/NotchPulse-Release-for-everyone/releases/latest/download/NotchPulse.dmg"
};

function initReleaseAutoUpdater() {
  const cached = sessionStorage.getItem("notchpulse_latest_release");
  if (cached) {
    try {
      const data = JSON.parse(cached);
      if (data && data.versionShort) {
        appReleaseInfo = data;
        applyLanguage(currentLang);
        updateDownloadLinks(appReleaseInfo.downloadUrl);
        return;
      }
    } catch (e) {}
  }

  fetch("https://api.github.com/repos/HieuKunn/NotchPulse-Release-for-everyone/releases/latest")
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

        sessionStorage.setItem("notchpulse_latest_release", JSON.stringify(appReleaseInfo));
        applyLanguage(currentLang);
        updateDownloadLinks(appReleaseInfo.downloadUrl);
      }
    })
    .catch(() => {
      // Graceful fallback to default v4.5
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
// 2. Language Switcher (7 Languages: VI, EN, DE, JA, ZH-TW, ZH-CN, ES)
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

  // Set HTML lang attribute for accessibility
  document.documentElement.setAttribute("lang", lang);

  // Update checkmarks in dropdown menu
  document.querySelectorAll(".lang-menu-item").forEach((btn) => {
    const isCurrent = btn.getAttribute("data-lang") === lang;
    btn.classList.toggle("active", isCurrent);
  });

  const dict = i18nData[lang] || i18nData.en;
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (dict[key]) {
      let text = dict[key];
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
  const cards = document.querySelectorAll(".testimonial-card");

  filterBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      filterBtns.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");

      const filterValue = btn.getAttribute("data-filter");

      cards.forEach((card) => {
        const rating = card.getAttribute("data-rating");
        if (filterValue === "all" || rating === filterValue) {
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
    });
  });
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
