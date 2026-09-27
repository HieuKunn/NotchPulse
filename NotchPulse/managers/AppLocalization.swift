//
//  AppLocalization.swift
//  NotchPulse
//
//  Created by Alexander on 2025-11-20.
//

import SwiftUI
import Defaults

struct L10n {
    @Default(.appLanguage) static var language: AppLanguage
    
    static func tr(_ key: String, lang: AppLanguage? = nil) -> String {
        let currentLang = lang ?? Defaults[.appLanguage]
        return translations[currentLang]?[key] ?? translations[.english]?[key] ?? key
    }
    
    private static let translations: [AppLanguage: [String: String]] = [
        .english: [
            // Tabs
            "General": "General",
            "Appearance": "Appearance",
            "Media": "Media",
            "Calendar": "Calendar",
            "HUD": "HUD",
            "SystemMonitor": "System Monitor",
            "FaceID": "Face ID",
            "Shelf": "Shelf",
            "Clipboard": "Clipboard",
            "Shortcuts": "Shortcuts",
            "Advanced": "Advanced",
            "Language": "Language",
            "About": "About",
            
            // General Tab
            "Notch style": "Notch style",
            "MacBook Notch": "MacBook Notch",
            "Dynamic Island": "Dynamic Island",
            "Dynamic Island top offset": "Dynamic Island top offset",
            "Notch open width": "Notch open width",
            "Compact": "Compact",
            "Standard": "Standard",
            "Wide": "Wide",
            "Extra wide": "Extra wide",
            "Show on all displays": "Show on all displays",
            "Preferred display": "Preferred display",
            "Automatically switch display": "Automatically switch display",
            "Menu bar": "Menu bar",
            "Show icon in menu bar": "Show icon in menu bar",
            "Launch at login": "Launch at login",
            "Show welcome onboarding": "Show welcome onboarding",
            "Quit NotchPulse": "Quit NotchPulse",
            "Behavior": "Behavior",
            "Open notch on hover": "Open notch on hover",
            "Extend hover area": "Extend hover area",
            "Hover detection range": "Hover detection range",
            "Enable haptics": "Enable haptics",
            "Haptic feedback": "Haptic feedback",
            "Minimum hover duration": "Minimum hover duration",
            
            // Appearance Tab
            "Corner radius scaling": "Corner radius scaling",
            "Enable shadow": "Enable shadow",
            "Enable gradient border": "Enable gradient border",
            "Glass effect": "Glass effect",
            "Custom accent color": "Custom accent color",
            "Use album art color": "Use album art color",
            
            // Media Tab
            "Media controller": "Media controller",
            "Sneak peek style": "Sneak peek style",
            "Show mirror": "Show mirror",
            "Now Playing": "Now Playing",
            "Apple Music": "Apple Music",
            "Spotify": "Spotify",
            "YouTube Music": "YouTube Music",
            "Default": "Default",
            "Inline": "Inline",
            "Hide notch": "Hide notch",
            "Always": "Always",
            "Now Playing Only": "Now Playing Only",
            "Never": "Never",
            
            // Calendar Tab
            "Show calendar": "Show calendar",
            "Hide completed reminders": "Hide completed reminders",
            "Hide all-day events": "Hide all-day events",
            "Auto-scroll to next event": "Auto-scroll to next event",
            "Always show full event titles": "Always show full event titles",
            "Calendars": "Calendars",
            "Alternate / Lunar Calendar": "Alternate / Lunar Calendar",
            
            // HUD Tab
            "Inline HUD": "Inline HUD",
            "Show closed notch HUD percentage": "Show closed notch HUD percentage",
            "Show open notch HUD": "Show open notch HUD",
            "HUD Replacement": "HUD Replacement",
            "Replace system HUD for Volume & Brightness": "Replace system HUD for Volume & Brightness",
            
            // System Monitor Tab
            "Enable system monitor": "Enable system monitor",
            "Show processes": "Show processes",
            "Battery charging limit": "Battery charging limit",
            
            // Face ID Tab
            "Face Unlock": "Face Unlock",
            "Enrolled Faces": "Enrolled Faces",
            "Password & Security": "Password & Security",
            "Recognition": "Recognition",
            "Lock Screen Media Player": "Lock Screen Media Player",
            "Show Media Player on Lock Screen": "Show Media Player on Lock Screen",
            "Show Real-time Synced Lyrics": "Show Real-time Synced Lyrics",
            "Enable Face ID": "Enable Face ID",
            "Face unlock": "Face unlock",
            "System authentication": "System authentication",
            "Liveness detection": "Liveness detection",
            "Camera": "Camera",
            "Sensitivity": "Sensitivity",
            "Match threshold": "Match threshold",
            "Quick auth": "Quick auth",
            "Terminal auth": "Terminal auth",
            
            // Shelf Tab
            "Enable shelf": "Enable shelf",
            "Open shelf by default if items are present": "Open shelf by default if items are present",
            "Expanded drag detection area": "Expanded drag detection area",
            "Drag hover expansion": "Drag hover expansion",
            "Copy items on drag": "Copy items on drag",
            "Remove from shelf after dragging": "Remove from shelf after dragging",
            
            // Clipboard Tab
            "Enable clipboard manager": "Enable clipboard manager",
            "Maximum history items": "Maximum history items",
            "Clear history on quit": "Clear history on quit",
            
            // Shortcuts Tab
            "Toggle Notch open/close": "Toggle Notch open/close",
            "Face ID quick auth shortcut": "Face ID quick auth shortcut",
            "Toggle Sneak Peek": "Toggle Sneak Peek",
            
            // Advanced Tab
            "Hide from screen recording": "Hide from screen recording",
            "Check for updates automatically": "Check for updates automatically",
            "Check for updates": "Check for updates",
            "Reset all settings": "Reset all settings",
            
            // Language Tab
            "App Language": "App Language",
            "Interface Language": "Interface Language",
            "Display Language": "Display Language",
            "Select language for NotchPulse interface": "Select language for NotchPulse interface",
            
            // About Tab
            "Version": "Version",
            "Developed with love": "Developed with love",
            "Website": "Website",
            "Source Code": "Source Code",
            "Settings": "Settings",
        ],
        .vietnamese: [
            // Tabs
            "General": "Cài đặt chung",
            "Appearance": "Giao diện",
            "Media": "Đa phương tiện",
            "Calendar": "Lịch & Sự kiện",
            "HUD": "Chỉ báo HUD",
            "SystemMonitor": "Giám sát hệ thống",
            "FaceID": "Face ID",
            "Shelf": "Ngăn chứa Shelf",
            "Clipboard": "Bộ nhớ tạm",
            "Shortcuts": "Phím tắt",
            "Advanced": "Nâng cao",
            "Language": "Ngôn ngữ",
            "About": "Giới thiệu",
            
            // General Tab
            "Notch style": "Kiểu Notch",
            "MacBook Notch": "Tai thỏ MacBook",
            "Dynamic Island": "Đảo động Dynamic Island",
            "Dynamic Island top offset": "Khoảng cách đỉnh Dynamic Island",
            "Notch open width": "Độ rộng khi mở Notch",
            "Compact": "Thu gọn (580px)",
            "Standard": "Tiêu chuẩn (740px)",
            "Wide": "Rộng (860px)",
            "Extra wide": "Cực rộng (940px)",
            "Show on all displays": "Hiển thị trên tất cả màn hình",
            "Preferred display": "Màn hình ưu tiên",
            "Automatically switch display": "Tự động chuyển màn hình",
            "Menu bar": "Thanh trạng thái",
            "Show icon in menu bar": "Hiển thị biểu tượng trên thanh Menu",
            "Launch at login": "Khởi động cùng máy tính",
            "Show welcome onboarding": "Xem lại hướng dẫn chào mừng",
            "Quit NotchPulse": "Thoát NotchPulse",
            "Behavior": "Hành vi hoạt động",
            "Open notch on hover": "Tự động mở Notch khi di chuột",
            "Extend hover area": "Mở rộng vùng nhận diện di chuột",
            "Hover detection range": "Phạm vi nhận diện di chuột",
            "Enable haptics": "Rung phản hồi haptic",
            "Haptic feedback": "Phản hồi xúc giác",
            "Minimum hover duration": "Thời gian giữ chuột tối thiểu",
            
            // Appearance Tab
            "Corner radius scaling": "Tự co dãn bán kính bo góc",
            "Enable shadow": "Bật đổ bóng",
            "Enable gradient border": "Bật viền chuyển màu Gradient",
            "Glass effect": "Hiệu ứng kính mờ (Glassmorphism)",
            "Custom accent color": "Màu nhấn tùy chỉnh",
            "Use album art color": "Đổi màu theo bìa bài hát",
            
            // Media Tab
            "Media controller": "Trình điều khiển nhạc",
            "Sneak peek style": "Kiểu xem nhanh Sneak Peek",
            "Show mirror": "Hiển thị xem trước camera",
            "Now Playing": "Đang phát hệ thống (Now Playing)",
            "Apple Music": "Apple Music",
            "Spotify": "Spotify",
            "YouTube Music": "YouTube Music",
            "Default": "Mặc định",
            "Inline": "Trên thanh Notch",
            "Hide notch": "Ẩn tai thỏ",
            "Always": "Luôn ẩn",
            "Now Playing Only": "Chỉ khi phát nhạc",
            "Never": "Không bao giờ ẩn",
            
            // Calendar Tab
            "Show calendar": "Hiển thị lịch",
            "Hide completed reminders": "Ẩn lời nhắc đã hoàn thành",
            "Hide all-day events": "Ẩn sự kiện cả ngày",
            "Auto-scroll to next event": "Tự động cuộn đến sự kiện tiếp theo",
            "Always show full event titles": "Luôn hiển thị đầy đủ tiêu đề sự kiện",
            "Calendars": "Danh sách lịch",
            "Alternate / Lunar Calendar": "Lịch âm / Lịch phụ",
            
            // HUD Tab
            "Inline HUD": "HUD tích hợp trên Notch",
            "Show closed notch HUD percentage": "Hiển thị % khi Notch đóng",
            "Show open notch HUD": "Hiển thị HUD khi Notch mở",
            "HUD Replacement": "Thay thế HUD hệ thống",
            "Replace system HUD for Volume & Brightness": "Thay thế HUD âm lượng và độ sáng mặc định",
            
            // System Monitor Tab
            "Enable system monitor": "Bật giám sát tài nguyên",
            "Show processes": "Hiển thị tiến trình chi tiết",
            "Battery charging limit": "Giới hạn sạc pin",
            
            // Face ID Tab
            "Face Unlock": "Mở khóa khuôn mặt Face ID",
            "Enrolled Faces": "Khuôn mặt đã đăng ký",
            "Password & Security": "Mật khẩu & Bảo mật",
            "Recognition": "Nhận diện & Độ sống thực",
            "Lock Screen Media Player": "Trình phát nhạc màn hình khóa",
            "Show Media Player on Lock Screen": "Hiển thị trình phát nhạc trên màn hình khóa",
            "Show Real-time Synced Lyrics": "Hiển thị lời bài hát khớp thời gian thực",
            "Enable Face ID": "Bật mở khóa khuôn mặt Face ID",
            "Face unlock": "Mở khóa màn hình bằng Face ID",
            "System authentication": "Xác thực quyền hệ thống / sudo",
            "Liveness detection": "Kiểm tra chuyển động mắt/khuôn mặt thật",
            "Camera": "Camera nhận diện",
            "Sensitivity": "Độ nhạy nhận diện",
            "Match threshold": "Ngưỡng khớp khuôn mặt",
            "Quick auth": "Phím tắt xác thực nhanh",
            "Terminal auth": "Xác thực dòng lệnh Terminal",
            
            // Shelf Tab
            "Enable shelf": "Bật ngăn chứa Shelf",
            "Open shelf by default if items are present": "Mở Shelf mặc định khi có tệp",
            "Expanded drag detection area": "Mở rộng vùng kéo thả tệp",
            "Drag hover expansion": "Phạm vi nhận diện kéo thả",
            "Copy items on drag": "Sao chép tệp khi kéo ra ngoài",
            "Remove from shelf after dragging": "Xóa khỏi Shelf sau khi kéo thả",
            
            // Clipboard Tab
            "Enable clipboard manager": "Bật quản lý bộ nhớ tạm",
            "Maximum history items": "Số lượng bản ghi tối đa",
            "Clear history on quit": "Xóa lịch sử khi thoát ứng dụng",
            
            // Shortcuts Tab
            "Toggle Notch open/close": "Phím tắt Đóng / Mở Notch",
            "Face ID quick auth shortcut": "Phím tắt xác thực nhanh Face ID",
            "Toggle Sneak Peek": "Phím tắt Xem nhanh Sneak Peek",
            
            // Advanced Tab
            "Hide from screen recording": "Ẩn khỏi quay màn hình & chụp ảnh",
            "Check for updates automatically": "Tự động kiểm tra bản cập nhật",
            "Check for updates": "Kiểm tra cập nhật ngay",
            "Reset all settings": "Đặt lại tất cả cài đặt",
            
            // Language Tab
            "App Language": "Ngôn ngữ ứng dụng",
            "Interface Language": "Ngôn ngữ giao diện",
            "Display Language": "Ngôn ngữ hiển thị",
            "Select language for NotchPulse interface": "Chọn ngôn ngữ hiển thị cho toàn bộ NotchPulse",
            
            // About Tab
            "Version": "Phiên bản",
            "Developed with love": "Phát triển với sự tận tâm",
            "Website": "Trang chủ",
            "Source Code": "Mã nguồn GitHub",
            "Settings": "Cài đặt",
        ],
        .traditionalChinese: [
            "General": "一般設定", "Appearance": "外觀風格", "Media": "媒體播放", "Calendar": "行事曆",
            "HUD": "HUD 提示", "SystemMonitor": "系統監視器", "FaceID": "Face ID", "Shelf": "暫存架",
            "Clipboard": "剪貼簿", "Shortcuts": "快捷鍵", "Advanced": "進階設定", "Language": "語言",
            "About": "關於", "Notch style": "瀏海樣式", "MacBook Notch": "MacBook 瀏海",
            "Dynamic Island": "動態島", "Show on all displays": "在所有螢幕顯示", "Preferred display": "偏好螢幕",
            "Open notch on hover": "懸停時展開", "Extend hover area": "擴大懸停區域", "Enable shelf": "啟用暫存架",
            "Enable Face ID": "啟用 Face ID", "App Language": "應用程式語言", "Version": "版本",
            "Show calendar": "顯示行事曆", "Alternate / Lunar Calendar": "農曆 / 副行事曆",
            "Face Unlock": "人臉解鎖", "Enrolled Faces": "已註冊臉孔", "Password & Security": "密碼與安全性",
            "Camera": "攝影機", "Recognition": "辨識與活體檢測", "Lock Screen Media Player": "鎖定畫面播放器",
            "Show Media Player on Lock Screen": "在鎖定畫面顯示音樂播放器", "Show Real-time Synced Lyrics": "顯示即時同步歌詞"
        ],
        .simplifiedChinese: [
            "General": "通用设置", "Appearance": "外观风格", "Media": "媒体控制", "Calendar": "日历",
            "HUD": "HUD 提示", "SystemMonitor": "系统监视器", "FaceID": "Face ID", "Shelf": "暂存架",
            "Clipboard": "剪贴板", "Shortcuts": "快捷键", "Advanced": "高级设置", "Language": "语言",
            "About": "关于", "Notch style": "刘海样式", "MacBook Notch": "MacBook 刘海",
            "Dynamic Island": "灵动岛", "Show on all displays": "在所有屏幕显示", "Preferred display": "首选屏幕",
            "Open notch on hover": "悬停时展开", "Extend hover area": "扩大悬停区域", "Enable shelf": "启用暂存架",
            "Enable Face ID": "启用 Face ID", "App Language": "应用程序语言", "Version": "版本",
            "Show calendar": "显示日历", "Alternate / Lunar Calendar": "农历 / 副日历",
            "Face Unlock": "人脸解锁", "Enrolled Faces": "已注册面孔", "Password & Security": "密码与安全性",
            "Camera": "摄像头", "Recognition": "识别与活体检测", "Lock Screen Media Player": "锁屏播放器",
            "Show Media Player on Lock Screen": "在锁屏显示媒体播放器", "Show Real-time Synced Lyrics": "显示实时同步歌词"
        ],
        .japanese: [
            "General": "一般", "Appearance": "外観", "Media": "メディア", "Calendar": "カレンダー",
            "HUD": "HUD 表示", "SystemMonitor": "システムモニター", "FaceID": "Face ID", "Shelf": "シェルフ",
            "Clipboard": "クリップボード", "Shortcuts": "ショートカット", "Advanced": "高度な設定", "Language": "言語",
            "About": "アプリ情報", "Notch style": "ノッチスタイル", "MacBook Notch": "MacBook ノッチ",
            "Dynamic Island": "ダイナミックアイランド", "Show on all displays": "すべてのディスプレイに表示",
            "Open notch on hover": "ホバーで展開", "Extend hover area": "ホバー領域を拡張", "Enable shelf": "シェルフを有効化",
            "Enable Face ID": "Face ID を有効化", "App Language": "言語設定", "Version": "バージョン",
            "Show calendar": "カレンダーを表示", "Alternate / Lunar Calendar": "旧暦 / 代替カレンダー",
            "Face Unlock": "Face ロック解除", "Enrolled Faces": "登録された顔", "Password & Security": "パスワードとセキュリティ",
            "Camera": "カメラ", "Recognition": "認識と生体検知", "Lock Screen Media Player": "ロック画面プレーヤー",
            "Show Media Player on Lock Screen": "ロック画面にメディアプレーヤーを表示", "Show Real-time Synced Lyrics": "同期歌詞を表示"
        ],
        .german: [
            "General": "Allgemein", "Appearance": "Erscheinungsbild", "Media": "Medien", "Calendar": "Kalender",
            "HUD": "HUD", "SystemMonitor": "Systemmonitor", "FaceID": "Face ID", "Shelf": "Ablage (Shelf)",
            "Clipboard": "Zwischenablage", "Shortcuts": "Kurzbefehle", "Advanced": "Erweitert", "Language": "Sprache",
            "About": "Über", "Notch style": "Notch-Stil", "MacBook Notch": "MacBook-Notch",
            "Dynamic Island": "Dynamic Island", "Show on all displays": "Auf allen Displays anzeigen",
            "Open notch on hover": "Bei Hover öffnen", "Extend hover area": "Hover-Bereich erweitern",
            "Enable shelf": "Shelf aktivieren", "Enable Face ID": "Face ID aktivieren",
            "App Language": "App-Sprache", "Version": "Version", "Show calendar": "Kalender anzeigen",
            "Alternate / Lunar Calendar": "Mondkalender / Alternativ",
            "Face Unlock": "Face-Entsperrung", "Enrolled Faces": "Registrierte Gesichter", "Password & Security": "Passwort & Sicherheit",
            "Camera": "Kamera", "Recognition": "Erkennung & Lebendigkeit", "Lock Screen Media Player": "Sperrbildschirm-Player",
            "Show Media Player on Lock Screen": "Medienplayer auf Sperrbildschirm anzeigen", "Show Real-time Synced Lyrics": "Synchronisierte Songtexte anzeigen"
        ],
        .french: [
            "General": "Général", "Appearance": "Apparence", "Media": "Multimédia", "Calendar": "Calendrier",
            "HUD": "Affichage HUD", "SystemMonitor": "Moniteur système", "FaceID": "Face ID", "Shelf": "Étagère (Shelf)",
            "Clipboard": "Presse-papiers", "Shortcuts": "Raccourcis", "Advanced": "Avancé", "Language": "Langue",
            "About": "À propos", "Notch style": "Style d'encoche", "MacBook Notch": "Encoche MacBook",
            "Dynamic Island": "Dynamic Island", "Show on all displays": "Afficher sur tous les écrans",
            "Open notch on hover": "Ouvrir au survol", "Extend hover area": "Étendre la zone de survol",
            "Enable shelf": "Activer le Shelf", "Enable Face ID": "Activer Face ID",
            "App Language": "Langue de l'app", "Version": "Version", "Show calendar": "Afficher le calendrier",
            "Alternate / Lunar Calendar": "Calendrier lunaire / alternatif",
            "Face Unlock": "Déverrouillage facial", "Enrolled Faces": "Visages enregistrés", "Password & Security": "Mot de passe et sécurité",
            "Camera": "Caméra", "Recognition": "Reconnaissance & Vitalité", "Lock Screen Media Player": "Lecteur écran de verrouillage",
            "Show Media Player on Lock Screen": "Afficher le lecteur multimédia sur l'écran verrouillé", "Show Real-time Synced Lyrics": "Afficher les paroles synchronisées"
        ],
        .spanish: [
            "General": "General", "Appearance": "Apariencia", "Media": "Multimedia", "Calendar": "Calendario",
            "HUD": "Indicador HUD", "SystemMonitor": "Monitor del sistema", "FaceID": "Face ID", "Shelf": "Estante (Shelf)",
            "Clipboard": "Portapapeles", "Shortcuts": "Atajos", "Advanced": "Avanzado", "Language": "Idioma",
            "About": "Acerca de", "Notch style": "Estilo de muesca", "MacBook Notch": "Notch MacBook",
            "Dynamic Island": "Isla Dinámica", "Show on all displays": "Mostrar en todas las pantallas",
            "Open notch on hover": "Abrir al pasar el cursor", "Extend hover area": "Extender área de cursor",
            "Enable shelf": "Activar Shelf", "Enable Face ID": "Activar Face ID",
            "App Language": "Idioma de la aplicación", "Version": "Versión", "Show calendar": "Mostrar calendario",
            "Alternate / Lunar Calendar": "Calendario lunar / alternativo",
            "Face Unlock": "Desbloqueo facial", "Enrolled Faces": "Rostros registrados", "Password & Security": "Contraseña y seguridad",
            "Camera": "Cámara", "Recognition": "Reconocimiento y viveza", "Lock Screen Media Player": "Reproductor en pantalla de bloqueo",
            "Show Media Player on Lock Screen": "Mostrar reproductor en pantalla de bloqueo", "Show Real-time Synced Lyrics": "Mostrar letras sincronizadas"
        ],
        .arabic: [
            "General": "عام", "Appearance": "المظهر", "Media": "الوسائط", "Calendar": "التقويم",
            "HUD": "مؤشر HUD", "SystemMonitor": "مراقب النظام", "FaceID": "Face ID", "Shelf": "الرف (Shelf)",
            "Clipboard": "الحافظة", "Shortcuts": "الاختصارات", "Advanced": "متقدم", "Language": "اللغة",
            "About": "حول التطبيق", "Notch style": "نمط النوتش", "MacBook Notch": "نوتch ماك بوك",
            "Dynamic Island": "الجزيرة التفاعلية", "Show on all displays": "عرض على كل الشاشات",
            "Open notch on hover": "فتح عند تحريك المؤشر", "Extend hover area": "توسيع منطقة التفاعل",
            "Enable shelf": "تفعيل الرف", "Enable Face ID": "تفعيل Face ID",
            "App Language": "لغة التطبيق", "Version": "الإصدار", "Show calendar": "عرض التقويم",
            "Alternate / Lunar Calendar": "التقويم الهجري / البديل",
            "Face Unlock": "فتح القفل بالوجه", "Enrolled Faces": "الوجوه المسجلة", "Password & Security": "كلمة المرور والأمان",
            "Camera": "الكاميرا", "Recognition": "التعرف والحيوية", "Lock Screen Media Player": "مشغل شاشة القفل",
            "Show Media Player on Lock Screen": "عرض مشغل الوسائط على شاشة القفل", "Show Real-time Synced Lyrics": "عرض الكلمات المتزامنة"
        ]
    ]
}

extension String {
    var localized: String {
        L10n.tr(self)
    }
}
