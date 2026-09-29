//
//  SpotlightTourView.swift
//  NotchPulse
//
//  Created by Antigravity on 2026-09-27.
//

import SwiftUI
import AppKit
import Defaults

// MARK: - Tour Step Model

enum SpotlightTourStep: Int, CaseIterable, Identifiable {
    case notchHover = 0
    case shakeToShelf
    case musicPlayer
    case calendarExpand
    case calendarFullMonth
    case clipboardManager
    case faceIDLock
    case menuBarSettings

    var id: Int { rawValue }

    func title(lang: AppLanguage) -> String {
        switch lang {
        case .vietnamese:
            switch self {
            case .notchHover: return "🕳️ Mở rộng Notch (Dynamic Island)"
            case .shakeToShelf: return "🤝 Lắc chuột để mở Shelf (Smart Shake)"
            case .musicPlayer: return "🎵 Trình phát nhạc & Lời bài hát"
            case .calendarExpand: return "📅 Mở rộng Lịch toàn tháng"
            case .calendarFullMonth: return "🗓️ Điều hướng Lịch & Ngày Âm Lịch"
            case .clipboardManager: return "📋 Bộ nhớ tạm Clipboard"
            case .faceIDLock: return "🔒 Bảo mật Face ID & Khóa màn hình"
            case .menuBarSettings: return "⚙️ Menu Bar & Cài đặt Tùy chỉnh"
            }
        case .traditionalChinese:
            switch self {
            case .notchHover: return "🕳️ 展開瀏海（動態島）"
            case .shakeToShelf: return "🤝 搖動滑鼠開啟暫存架 (Smart Shake)"
            case .musicPlayer: return "🎵 音樂播放器與即時歌詞"
            case .calendarExpand: return "📅 展開全月行事曆"
            case .calendarFullMonth: return "🗓️ 行事曆導覽與農曆資訊"
            case .clipboardManager: return "📋 剪貼簿歷史紀錄與片段"
            case .faceIDLock: return "🔒 Face ID 與螢幕鎖定安全性"
            case .menuBarSettings: return "⚙️ 選單列與自訂設定"
            }
        case .simplifiedChinese:
            switch self {
            case .notchHover: return "🕳️ 展开刘海（灵动岛）"
            case .shakeToShelf: return "🤝 晃动鼠标打开暂存架 (Smart Shake)"
            case .musicPlayer: return "🎵 音乐播放器与实时歌词"
            case .calendarExpand: return "📅 展开全月日历"
            case .calendarFullMonth: return "🗓️ 日历导航与农历信息"
            case .clipboardManager: return "📋 剪贴板历史记录与片段"
            case .faceIDLock: return "🔒 Face ID 与屏幕锁定安全性"
            case .menuBarSettings: return "⚙️ 菜单栏与自定义设置"
            }
        case .japanese:
            switch self {
            case .notchHover: return "🕳️ ノッチ（Dynamic Island）の展開"
            case .shakeToShelf: return "🤝 マウスシェイクでシェルフ展開"
            case .musicPlayer: return "🎵 音楽プレイヤー＆同期歌詞"
            case .calendarExpand: return "📅 月間カレンダーの展開"
            case .calendarFullMonth: return "🗓️ カレンダー操作と旧暦情報"
            case .clipboardManager: return "📋 クリップボード履歴＆スニペット"
            case .faceIDLock: return "🔒 Face ID＆画面ロックセキュリティ"
            case .menuBarSettings: return "⚙️ メニューバーとカスタム設定"
            }
        case .german:
            switch self {
            case .notchHover: return "🕳️ Notch erweitern (Dynamic Island)"
            case .shakeToShelf: return "🤝 Schütteln zum Öffnen des Shelf"
            case .musicPlayer: return "🎵 Musik-Player & Songtexte"
            case .calendarExpand: return "📅 Vollmonatskalender erweitern"
            case .calendarFullMonth: return "🗓️ Kalendernavigation & Monddetails"
            case .clipboardManager: return "📋 Zwischenablage-Verlauf"
            case .faceIDLock: return "🔒 Face ID & Bildschirmsperre"
            case .menuBarSettings: return "⚙️ Menüleiste & Einstellungen"
            }
        case .french:
            switch self {
            case .notchHover: return "🕳️ Déployer l'encoche (Dynamic Island)"
            case .shakeToShelf: return "🤝 Secouer pour ouvrir le Shelf"
            case .musicPlayer: return "🎵 Lecteur de musique & Paroles"
            case .calendarExpand: return "📅 Déployer le calendrier mensuel"
            case .calendarFullMonth: return "🗓️ Navigation & Calendrier lunaire"
            case .clipboardManager: return "📋 Historique du presse-papiers"
            case .faceIDLock: return "🔒 Face ID & Sécurité de l'écran"
            case .menuBarSettings: return "⚙️ Barre des menus & Réglages"
            }
        case .spanish:
            switch self {
            case .notchHover: return "🕳️ Expandir Notch (Dynamic Island)"
            case .shakeToShelf: return "🤝 Agitar para abrir el Shelf"
            case .musicPlayer: return "🎵 Reproductor de música y letras"
            case .calendarExpand: return "📅 Expandir calendario mensual"
            case .calendarFullMonth: return "🗓️ Navegación y calendario lunar"
            case .clipboardManager: return "📋 Historial del portapapeles"
            case .faceIDLock: return "🔒 Face ID y seguridad de bloqueo"
            case .menuBarSettings: return "⚙️ Barra de menús y Ajustes"
            }
        case .arabic:
            switch self {
            case .notchHover: return "🕳️ توسيع النوتش (الجزيرة التفاعلية)"
            case .shakeToShelf: return "🤝 هز الفأرة لفتح الرف (Shelf)"
            case .musicPlayer: return "🎵 مشغل الموسيقى والكلمات"
            case .calendarExpand: return "📅 توسيع تقويم الشهر بالكامل"
            case .calendarFullMonth: return "🗓️ التنقل في التقويم والتفاصيل"
            case .clipboardManager: return "📋 سجل الحافظة والقصاصات"
            case .faceIDLock: return "🔒 أمان Face ID وقفل الشاشة"
            case .menuBarSettings: return "⚙️ شريط القوائم والتخصيصات"
            }
        case .english:
            switch self {
            case .notchHover: return "🕳️ Expand Notch (Dynamic Island)"
            case .shakeToShelf: return "🤝 Shake to Open Shelf (Smart Shake)"
            case .musicPlayer: return "🎵 Music Player & Synced Lyrics"
            case .calendarExpand: return "📅 Expand Full Month Calendar"
            case .calendarFullMonth: return "🗓️ Full Month Navigation & Lunar Details"
            case .clipboardManager: return "📋 Clipboard History & Snippets"
            case .faceIDLock: return "🔒 Face ID & Lock Screen Security"
            case .menuBarSettings: return "⚙️ Menu Bar & Customizations"
            }
        }
    }

    func badgeText(lang: AppLanguage) -> String {
        let current = rawValue + 1
        let total = SpotlightTourStep.allCases.count
        switch lang {
        case .vietnamese: return "Bước \(current)/\(total)"
        case .traditionalChinese: return "步驟 \(current)/\(total)"
        case .simplifiedChinese: return "步骤 \(current)/\(total)"
        case .japanese: return "ステップ \(current)/\(total)"
        case .german: return "Schritt \(current)/\(total)"
        case .french: return "Étape \(current)/\(total)"
        case .spanish: return "Paso \(current)/\(total)"
        case .arabic: return "الخطوة \(current)/\(total)"
        case .english: return "Step \(current)/\(total)"
        }
    }

    func description(lang: AppLanguage) -> String {
        switch lang {
        case .vietnamese:
            switch self {
            case .notchHover:
                return "Di chuột vào khu vực Notch ở góc trên giữa màn hình để mở rộng bảng điều khiển nhanh. Rời chuột 250ms Notch sẽ tự thu gọn mượt mà."
            case .shakeToShelf:
                return "Khi bạn đang nắm/kéo (drag) một file, hình ảnh hoặc đoạn văn bản, hãy lắc nhẹ chuột trái phải nhanh 4 lần liên tục. Khay lưu tạm Notch Shelf sẽ lập tức bung ra hứng file!"
            case .musicPlayer:
                return "Click vào Bìa Album để mở nhanh App nhạc tương ứng. Click vào Tên bài hát hoặc biểu tượng Micro để mở Lời bài hát cuộn theo thời gian thực (Synced Lyrics)."
            case .calendarExpand:
                return "Click trực tiếp vào phần hiển thị Ngày & Tháng bên trong Notch để lập tức mở rộng toàn bộ lưới lịch tháng tương tác."
            case .calendarFullMonth:
                return "Dùng 2 nút mũi tên `<` và `>` bên trái để chuyển tháng, và nhấn vào biểu tượng Mặt Trăng bên phải để xem chi tiết Ngày/Tháng Âm Lịch, Can Chi & Giờ hoàng đạo."
            case .clipboardManager:
                return "Tự động lưu lại toàn bộ lịch sử nội dung đã Copy. Click vào dòng bất kỳ để Paste lại nhanh, ghim 📌 nội dung quan trọng hoặc tìm kiếm lịch sử."
            case .faceIDLock:
                return "Di chuột vào Notch để tự động quét nhận diện Face ID / Touch ID giải mã thông tin. Khi dùng màn hình rời, Face ID sẽ hạ xuống mượt mà bên màn hình có Camera thật."
            case .menuBarSettings:
                return "Click icon Bánh răng ⚙️ ở góc trên bên phải Notch (khi mở) để mở Cài đặt, chuyển màn hình hiển thị, chỉnh độ cong góc hoặc các hiệu ứng ánh sáng."
            }
        case .traditionalChinese:
            switch self {
            case .notchHover:
                return "將滑鼠懸停在螢幕頂部中央的瀏海區域即可展開快捷控制面板。移開滑鼠 250 毫秒後瀏海將自動平滑收合。"
            case .shakeToShelf:
                return "當您正在拖曳檔案、圖片或文字片段時，快速左右晃動滑鼠 4 次，Notch 暫存架便會立即彈出承接您的檔案！"
            case .musicPlayer:
                return "點擊專輯封面可快速切換至對應音樂 App。點擊歌曲名稱或麥克風圖示即可開啟即時捲動歌詞 (Synced Lyrics)。"
            case .calendarExpand:
                return "直接點擊瀏海內的日期與月份資訊，即可立即展開完整的互動式月曆網格。"
            case .calendarFullMonth:
                return "使用左側的 `<` 和 `>` 按鈕切換月份，點擊右側的月亮圖示即可查看農曆日期、天干地支與吉時吉日。"
            case .clipboardManager:
                return "自動記錄您複製過的所有文字、圖片與連結。點擊任意項目即可快速重新複製，亦可釘選 📌 重要內容。"
            case .faceIDLock:
                return "將滑鼠懸停於瀏海即可自動進行 Face ID / Touch ID 辨識。連接外接螢幕時，Face ID 會自動於具備實體鏡頭的螢幕展開。"
            case .menuBarSettings:
                return "點擊展開瀏海右上角的齒輪 ⚙️ 圖示即可開啟設定，隨心切換顯示螢幕、調整圓角弧度或燈光特效。"
            }
        case .simplifiedChinese:
            switch self {
            case .notchHover:
                return "将鼠标悬停在屏幕顶部中央的刘海区域即可展开快捷控制面板。移开鼠标 250 毫秒后刘海将自动平滑收起。"
            case .shakeToShelf:
                return "当您正在拖拽文件、图片或文本片段时，快速左右晃动鼠标 4 次，Notch 暂存架便会立即弹出承接您的文件！"
            case .musicPlayer:
                return "点击专辑封面可快速切换至对应音乐 App。点击歌曲名称或麦克风图标即可开启实时滚动歌词 (Synced Lyrics)。"
            case .calendarExpand:
                return "直接点击刘海内的日期与月份信息，即可立即展开完整的交互式月历网格。"
            case .calendarFullMonth:
                return "使用左侧的 `<` 和 `>` 按钮切换月份，点击右侧的月亮图标即可查看农历日期、天干地支与黄道吉时。"
            case .clipboardManager:
                return "自动记录您复制过的所有文本、图片与链接。点击任意项目即可快速重新复制，亦可固定 📌 重要内容。"
            case .faceIDLock:
                return "将鼠标悬停于刘海即可自动进行 Face ID / Touch ID 识别。连接外接显示器时，Face ID 会自动在具备实体摄像头的屏幕展开。"
            case .menuBarSettings:
                return "点击展开刘海右上角的齿轮 ⚙️ 图标即可打开设置，随心切换显示器、调整圆角弧度或灯光特效。"
            }
        case .japanese:
            switch self {
            case .notchHover:
                return "画面上部中央のノッチにカーソルを合わせるとクイックコントロールが展開します。カーソルを離して250ミリ秒後に自動でスムーズに格納されます。"
            case .shakeToShelf:
                return "ファイル、画像、テキストをドラッグ中にマウスを素早く左右に4回振ると、Notch Shelf が即座に開いてファイルを受け取ります！"
            case .musicPlayer:
                return "アルバムアートをクリックして音楽アプリを開きます。曲名または歌詞アイコンをクリックすると、リアルタイム同期歌詞が表示されます。"
            case .calendarExpand:
                return "ノッチ内の日付と月表示を直接クリックすると、30日間のインタラクティブな月間カレンダーグリッドが展開します。"
            case .calendarFullMonth:
                return "左側の `<` と `>` ボタンで月を切り替え、右側の月アイコンをクリックすると旧暦や詳細情報を確認できます。"
            case .clipboardManager:
                return "コピーしたテキスト、画像、リンクを自動記録します。項目をクリックして即座に再コピーしたり、ピン留め 📌 できます。"
            case .faceIDLock:
                return "ノッチにホバーすると Face ID / Touch ID で自動認証します。外部ディスプレイ接続時は実カメラのある画面にドロップダウンします。"
            case .menuBarSettings:
                return "展開したノッチ右上の歯車 ⚙️ アイコンをクリックして設定を開き、ディスプレイ切替や角丸、発光エフェクトを調整できます。"
            }
        case .german:
            switch self {
            case .notchHover:
                return "Bewegen Sie den Mauszeiger über die Notch oben in der Mitte des Bildschirms, um die Schnellsteuerung zu öffnen. Nach 250 ms ohne Maus schließt sie sich automatisch sanft."
            case .shakeToShelf:
                return "Während Sie eine Datei, ein Bild oder einen Text ziehen, schütteln Sie die Maus viermal schnell nach links und rechts. Das Notch Shelf öffnet sich sofort!"
            case .musicPlayer:
                return "Klicken Sie auf das Album-Cover, um die Musik-App zu öffnen. Klicken Sie auf den Songtitel für synchron mitlaufende Songtexte."
            case .calendarExpand:
                return "Klicken Sie direkt auf die Datums- und Monatsanzeige in der Notch, um das vollständige Monatsraster zu öffnen."
            case .calendarFullMonth:
                return "Verwenden Sie die Schaltflächen `<` und `>` zum Wechseln der Monate und das Mondsymbol für Mondkalenderdetails."
            case .clipboardManager:
                return "Speichert automatisch kopierte Texte, Bilder und Links. Klicken Sie auf einen Eintrag zum erneuten Kopieren oder Anpinnen 📌."
            case .faceIDLock:
                return "Bewegen Sie die Maus über die Notch für automatische Face ID/Touch ID-Erkennung. Bei externen Monitoren öffnet sich Face ID am Kamerabildschirm."
            case .menuBarSettings:
                return "Klicken Sie auf das Zahnrad ⚙️ oben rechts in der geöffneten Notch, um Einstellungen zu öffnen und Effekte anzupassen."
            }
        case .french:
            switch self {
            case .notchHover:
                return "Survolez l'encoche en haut au centre de votre écran pour afficher les commandes rapides. Éloignez la souris pendant 250 ms pour la refermer en douceur."
            case .shakeToShelf:
                return "Pendant le glissement d'un fichier, d'une image ou d'un texte, secouez rapidement la souris de gauche à droite 4 fois. Le Shelf s'ouvrira immédiatement !"
            case .musicPlayer:
                return "Cliquez sur la pochette pour ouvrir l'app musicale. Cliquez sur le titre pour afficher les paroles défilantes en temps réel."
            case .calendarExpand:
                return "Cliquez sur la date et le mois dans l'encoche pour afficher la grille complète du calendrier interactif."
            case .calendarFullMonth:
                return "Utilisez les boutons `<` et `>` pour changer de mois et cliquez sur l'icône de lune pour voir les détails lunaires."
            case .clipboardManager:
                return "Conserve automatiquement vos textes, images et liens copiés. Cliquez sur un élément pour le copier à nouveau ou l'épingler 📌."
            case .faceIDLock:
                return "Survolez l'encoche pour vous authentifier avec Face ID ou Touch ID. Sur écran externe, Face ID s'affiche sous votre vraie caméra."
            case .menuBarSettings:
                return "Cliquez sur l'engrenage ⚙️ en haut à droite de l'encoche pour ouvrir les Réglages et personnaliser les effets."
            }
        case .spanish:
            switch self {
            case .notchHover:
                return "Pase el cursor sobre el Notch en la parte superior central de la pantalla para desplegar los controles rápidos. Al retirar el cursor durante 250 ms se cerrará suavemente."
            case .shakeToShelf:
                return "Mientras arrastra cualquier archivo, imagen o texto, mueva el ratón rápidamente de izquierda a derecha 4 veces seguidas. ¡El Shelf se abrirá al instante!"
            case .musicPlayer:
                return "Haga clic en la carátula para abrir la app de música. Haga clic en el título para ver las letras sincronizadas en tiempo real."
            case .calendarExpand:
                return "Haga clic en la fecha y el mes dentro del Notch para desplegar la cuadrícula completa del calendario mensual."
            case .calendarFullMonth:
                return "Use los botones `<` y `>` para cambiar de mes y haga clic en el icono de luna para ver detalles lunares."
            case .clipboardManager:
                return "Guarda automáticamente textos, imágenes y enlaces copiados. Haga clic en cualquier elemento para volver a copiarlo o fijarlo 📌."
            case .faceIDLock:
                return "Pase el cursor sobre el Notch para autenticarse con Face ID o Touch ID. En pantalla externa, Face ID se despliega bajo su cámara real."
            case .menuBarSettings:
                return "Haga clic en el engranaje ⚙️ arriba a la derecha del Notch abierto para abrir Ajustes y personalizar los efectos."
            }
        case .arabic:
            switch self {
            case .notchHover:
                return "مرر المؤشر فوق النوتش في أعلى منتصف الشاشة لتوسيع عناصر التحكم السريعة. سيتراجع النوتش بسلاسة بعد إبعاد المؤشر بـ 250 مللي ثانية."
            case .shakeToShelf:
                return "أثناء سحب أي ملف أو صورة أو نص، هز الفأرة بسرعة يميناً ويساراً 4 مرات متتالية، وسيفتح رف Notch فوراً لالتقاط ملفك!"
            case .musicPlayer:
                return "انقر فوق غلاف الألبوم لفتح تطبيق الموسيقى النشط. انقر فوق اسم الأغنية لعرض كلمات الأغاني المتزامنة في الوقت الفعلي."
            case .calendarExpand:
                return "انقر مباشرة على التاريخ والشهر داخل النوتش لتوسيع شبكة التقويم التفاعلية الكاملة."
            case .calendarFullMonth:
                return "استخدم زرّي `<` و `>` للتنقل بين الأشهر، وانقر على أيقونة القمر لعرض تفاصيل التقويم القمري."
            case .clipboardManager:
                return "يحفظ تلقائياً النصوص والصور والروابط المنسوخة. انقر فوق أي عنصر لإعادة نسخه أو تثبيته 📌."
            case .faceIDLock:
                return "مرر المؤشر فوق النوتش للمصادقة التلقائية باستخدام Face ID أو Touch ID. عند التوصيل بشاشة خارجية، يظهر Face ID تحت كاميرتك الفعلية."
            case .menuBarSettings:
                return "انقر فوق الترس ⚙️ أعلى يمين النوتش المفتوح لفتح الإعدادات وتبديل الشاشات وتخصيص المؤثرات."
            }
        case .english:
            switch self {
            case .notchHover:
                return "Hover your cursor over the Notch at the top center of your screen to expand the quick controls. Move mouse away for 250ms to smoothly auto-close."
            case .shakeToShelf:
                return "While dragging any file, image, or text snippet, quickly shake your mouse left and right 4 times in a row. The Notch Shelf will immediately pop open to catch your file!"
            case .musicPlayer:
                return "Click the Album Art to jump directly into the active music app. Click the song title or lyrics icon to view real-time synced scrolling lyrics."
            case .calendarExpand:
                return "Click directly on the Month & Date header inside the Notch to expand the full 30-day interactive calendar grid."
            case .calendarFullMonth:
                return "Use the `<` and `>` buttons on the left to switch months, see today highlighted, and click the Moon icon on the right to view detailed Lunar calendar dates & Can Chi."
            case .clipboardManager:
                return "Automatically keeps track of your copied text, images, and links. Click any item to re-paste, pin 📌 essentials, or search your clipboard history."
            case .faceIDLock:
                return "Hover over the Notch to automatically authenticate using Face ID or Touch ID. When connected to an external display, Face ID drops down under your physical camera."
            case .menuBarSettings:
                return "Click the Gear ⚙️ icon at the top right inside the open Notch to switch display monitors, customize corner radius, adjust lighting effects, or open Settings."
            }
        }
    }

    var iconName: String {
        switch self {
        case .notchHover: return "arrow.up.and.person.rectangle.portrait"
        case .shakeToShelf: return "hand.draw.fill"
        case .musicPlayer: return "music.note.list"
        case .calendarExpand: return "calendar.badge.plus"
        case .calendarFullMonth: return "calendar.badge.clock"
        case .clipboardManager: return "doc.on.clipboard.fill"
        case .faceIDLock: return "faceid"
        case .menuBarSettings: return "gearshape.fill"
        }
    }

    /// Calculate highlight frame relative to screen size (width, height)
    @MainActor
    func targetFrame(screenSize: CGSize) -> CGRect {
        let screenWidth = screenSize.width

        switch self {
        case .notchHover:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 175
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .shakeToShelf:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 200
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .musicPlayer:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 195
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .calendarExpand:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 240
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .calendarFullMonth:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 265
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .clipboardManager:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 250
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .faceIDLock:
            let width: CGFloat = 320
            let height: CGFloat = 80
            return CGRect(x: (screenWidth - width) / 2, y: 0, width: width, height: height)

        case .menuBarSettings:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 175
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)
        }
    }
}

// MARK: - Hole Punch Shape (Spotlight Cutout)

struct SpotlightCutoutShape: Shape {
    let targetRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Whole screen rect
        path.addRect(rect)
        // Subtracted cutout hole
        let hole = Path(roundedRect: targetRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        path.addPath(hole)
        return path
    }
}

// MARK: - Fullscreen Pass-Through Backdrop View

struct SpotlightBackdropView: View {
    @ObservedObject var manager = SpotlightTourManager.shared

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if manager.currentCutoutRect.width > 0 && manager.currentCutoutRect.height > 0 {
                    // 1. Dark Overlay with Cutout (Even-Odd hole punch)
                    SpotlightCutoutShape(
                        targetRect: manager.currentCutoutRect,
                        cornerRadius: manager.currentCornerRadius
                    )
                    .fill(Color.black.opacity(0.75), style: FillStyle(eoFill: true))
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.currentCutoutRect)
                    .ignoresSafeArea()

                    // 2. Bright Glowing Pure White Frame around target
                    RoundedRectangle(cornerRadius: manager.currentCornerRadius, style: .continuous)
                        .stroke(Color.white, lineWidth: 2.5)
                        .shadow(color: Color.white.opacity(0.85), radius: 8)
                        .shadow(color: Color.white.opacity(0.4), radius: 18)
                        .frame(width: max(0, manager.currentCutoutRect.width), height: max(0, manager.currentCutoutRect.height))
                        .position(x: manager.currentCutoutRect.midX, y: manager.currentCutoutRect.midY)
                        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.currentCutoutRect)
                }
            }
        }
    }
}

// MARK: - Tooltip Card View

struct SpotlightTooltipCard: View {
    let step: SpotlightTourStep
    let language: AppLanguage
    let onNext: () -> Void
    let onPrev: () -> Void
    let onClose: () -> Void
    let isFirst: Bool
    let isLast: Bool

    private var backText: String {
        switch language {
        case .vietnamese: return "Quay lại"
        case .traditionalChinese: return "返回"
        case .simplifiedChinese: return "返回"
        case .japanese: return "戻る"
        case .german: return "Zurück"
        case .french: return "Retour"
        case .spanish: return "Atrás"
        case .arabic: return "رجوع"
        case .english: return "Back"
        }
    }

    private var nextText: String {
        if isLast {
            switch language {
            case .vietnamese: return "Hoàn thành"
            case .traditionalChinese: return "完成"
            case .simplifiedChinese: return "完成"
            case .japanese: return "完了"
            case .german: return "Fertig"
            case .french: return "Terminer"
            case .spanish: return "Finalizar"
            case .arabic: return "إنهاء"
            case .english: return "Finish"
            }
        } else {
            switch language {
            case .vietnamese: return "Tiếp theo"
            case .traditionalChinese: return "下一步"
            case .simplifiedChinese: return "下一步"
            case .japanese: return "次へ"
            case .german: return "Weiter"
            case .french: return "Suivant"
            case .spanish: return "Siguiente"
            case .arabic: return "التالي"
            case .english: return "Next"
            }
        }
    }

    private var closeHelpText: String {
        switch language {
        case .vietnamese: return "Đóng hướng dẫn (Notch vẫn mở)"
        case .traditionalChinese: return "關閉導覽（保持瀏海開啟）"
        case .simplifiedChinese: return "关闭导览（保持刘海开启）"
        case .japanese: return "ガイドを閉じる（ノッチは開いたまま）"
        case .german: return "Tour schließen (Notch bleibt offen)"
        case .french: return "Fermer le guide (L'encoche reste ouverte)"
        case .spanish: return "Cerrar guía (El notch permanece abierto)"
        case .arabic: return "إغلاق الجولة (يبقى النوتش مفتوحاً)"
        case .english: return "Close guide (Notch stays open)"
        }
    }

    private var faceIDPromptText: String {
        switch language {
        case .vietnamese: return "Bạn có muốn thiết lập Face ID ngay không?"
        case .traditionalChinese: return "您想立即設定 Face ID 嗎？"
        case .simplifiedChinese: return "您想立即设置 Face ID 吗？"
        case .japanese: return "今すぐ Face ID を設定しますか？"
        case .german: return "Möchten Sie Face ID jetzt einrichten?"
        case .french: return "Voulez-vous configurer Face ID maintenant ?"
        case .spanish: return "¿Desea configurar Face ID ahora?"
        case .arabic: return "هل ترغب في إعداد Face ID الآن؟"
        case .english: return "Would you like to set up Face ID now?"
        }
    }

    private var faceIDYesText: String {
        switch language {
        case .vietnamese: return "Có (Thiết lập ngay)"
        case .traditionalChinese: return "是 (立即設定)"
        case .simplifiedChinese: return "是 (立即设置)"
        case .japanese: return "はい (今すぐ設定)"
        case .german: return "Ja (Jetzt einrichten)"
        case .french: return "Oui (Configurer)"
        case .spanish: return "Sí (Configurar ahora)"
        case .arabic: return "نعم (إعداد الآن)"
        case .english: return "Yes (Set up now)"
        }
    }

    private var faceIDNoText: String {
        switch language {
        case .vietnamese: return "Không (Để sau)"
        case .traditionalChinese: return "否 (稍後)"
        case .simplifiedChinese: return "否 (稍后)"
        case .japanese: return "いいえ (後で)"
        case .german: return "Nein (Später)"
        case .french: return "Non (Plus tard)"
        case .spanish: return "No (Más tarde)"
        case .arabic: return "لا (لاحقاً)"
        case .english: return "No (Later)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(spacing: 10) {
                Image(systemName: step.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.black)

                Text(step.title(lang: language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Spacer()

                Text(step.badgeText(lang: language))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.08)))
                    .foregroundColor(Color.black.opacity(0.75))

                // Quick exit X button: Closes guide and keeps Notch open
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.black.opacity(0.45))
                }
                .buttonStyle(PlainButtonStyle())
                .help(closeHelpText)
            }

            Divider()
                .background(Color.black.opacity(0.12))

            // Body Description
            Text(step.description(lang: language))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.black.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Step 6 (Face ID): Interactive setup prompt with "Yes" & "No" buttons
            if step == .faceIDLock {
                faceIDSetupPromptSection
            }

            Spacer(minLength: 0)

            // Action Buttons Footer
            HStack(spacing: 8) {
                Spacer()

                if !isFirst {
                    Button(action: onPrev) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(backText)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.08)))
                        .foregroundColor(Color.black.opacity(0.85))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(nextText)
                        if !isLast {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black)
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 430, height: (step == .faceIDLock) ? 290 : 240)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        )
    }

    @ViewBuilder
    private var faceIDSetupPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .foregroundColor(.black)
                    .font(.system(size: 13))

                Text(faceIDPromptText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
            }

            HStack(spacing: 8) {
                Button(action: {
                    SpotlightTourManager.shared.startFaceIDSetupFromTour {
                        onNext()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(faceIDYesText)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
                    .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onNext) {
                    Text(faceIDNoText)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.08)))
                        .foregroundColor(Color.black.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
    }
}

// MARK: - Dedicated Tooltip Card Host View

struct SpotlightTooltipCardHostView: View {
    @ObservedObject var manager = SpotlightTourManager.shared

    var body: some View {
        SpotlightTooltipCard(
            step: manager.currentStep,
            language: manager.language,
            onNext: { manager.nextStep() },
            onPrev: { manager.prevStep() },
            onClose: { manager.closeTour() },
            isFirst: manager.currentStepIndex == 0,
            isLast: manager.currentStepIndex == SpotlightTourStep.allCases.count - 1
        )
    }
}

// MARK: - Tour Manager Window Controller

@MainActor
final class SpotlightTourManager: ObservableObject {
    static let shared = SpotlightTourManager()

    /// True while the spotlight tour overlay is visible. ContentView uses this flag
    /// to suppress all auto-close timers so the notch stays open during the tour.
    @Published var isActive: Bool = false

    @Published var currentStepIndex: Int = 0
    @Published var currentCutoutRect: CGRect = {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        let width: CGFloat = 740
        let height: CGFloat = 190
        return CGRect(x: (screen.width - width) / 2, y: 0, width: width, height: height)
    }()
    @Published var currentCornerRadius: CGFloat = 26
    @Published var language: AppLanguage = .english

    var currentStep: SpotlightTourStep {
        SpotlightTourStep(rawValue: currentStepIndex) ?? .notchHover
    }

    private var backdropWindow: NSWindow?
    private var cardWindow: NSWindow?
    private var faceIDPhaseObserver: NSObjectProtocol?
    private var activeScreen: NSScreen?

    func showTour(useAppLanguage: Bool = true) {
        closeTour()

        let targetScreen: NSScreen?
        if Defaults[.showOnAllDisplays] {
            targetScreen = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main
                ?? NSScreen.screens.first
        } else {
            let coordinator = NotchPulseViewCoordinator.shared
            let appDelegate = NSApp.delegate as? AppDelegate
            targetScreen = (coordinator.preferredScreenUUID.flatMap({ NSScreen.screen(withUUID: $0) }))
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? appDelegate?.window?.screen
                ?? NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
        guard let mainScreen = targetScreen else { return }
        self.activeScreen = mainScreen

        self.language = useAppLanguage ? Defaults[.appLanguage] : .english
        self.currentStepIndex = 0

        let coordinator = NotchPulseViewCoordinator.shared
        coordinator.alwaysShowTabs = true
        Defaults[.notchPulseShelf] = true
        Defaults[.enableClipboardManager] = true
        Defaults[.showCalendar] = true

        // Compute initial cutout immediately so backdrop and card open at the right location
        let targetVM: NotchPulseViewModel
        let appDelegate = NSApp.delegate as? AppDelegate
        targetVM = appDelegate?.vm ?? NotchPulseViewModel()
        let (initialRect, initialRadius) = computeCutoutRect(for: currentStep, screen: mainScreen, targetVM: targetVM)
        self.currentCutoutRect = initialRect
        self.currentCornerRadius = initialRadius

        // 1. Create Non-Blocking Backdrop Window (ignoresMouseEvents = true so all clicks pass through)
        let backdrop = NSWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backdrop.level = .screenSaver
        backdrop.backgroundColor = .clear
        backdrop.isOpaque = false
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true // Full pass-through for Notch, Desktop, and Apps!
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.isReleasedWhenClosed = false
        backdrop.contentView = NSHostingView(rootView: SpotlightBackdropView())
        self.backdropWindow = backdrop

        // 2. Create Floating Tooltip Card Window (sized strictly to the 430px card)
        let initialCardRect = cardRect(for: currentStep, screen: mainScreen)
        let card = NSPanel(
            contentRect: initialCardRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        card.level = .screenSaver + 1
        card.backgroundColor = .clear
        card.isOpaque = false
        card.hasShadow = false
        card.ignoresMouseEvents = false // Card captures clicks on its own buttons
        card.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        card.isReleasedWhenClosed = false
        card.contentView = NSHostingView(rootView: SpotlightTooltipCardHostView())
        self.cardWindow = card

        isActive = true
        SharingStateManager.shared.preventNotchClose = true

        updateLiveUIState(for: currentStep)

        // Position card properly below the computed cutout
        let positionedCardRect = cardRect(for: currentStep, screen: mainScreen)
        card.setFrame(positionedCardRect, display: true)

        backdrop.orderFrontRegardless()
        card.orderFrontRegardless()
    }

    func updateLiveCutout(rect: CGRect, radius: CGFloat) {
        guard isActive else { return }
        if abs(currentCutoutRect.origin.x - rect.origin.x) < 0.5 &&
           abs(currentCutoutRect.origin.y - rect.origin.y) < 0.5 &&
           abs(currentCutoutRect.width - rect.width) < 0.5 &&
           abs(currentCutoutRect.height - rect.height) < 0.5 &&
           abs(currentCornerRadius - radius) < 0.5 {
            return
        }
        self.currentCutoutRect = rect
        self.currentCornerRadius = radius
        if let screen = activeScreen, let card = cardWindow {
            let newCardRect = cardRect(for: currentStep, screen: screen)
            if abs(card.frame.origin.y - newCardRect.origin.y) > 1.5 ||
               abs(card.frame.origin.x - newCardRect.origin.x) > 1.5 ||
               abs(card.frame.height - newCardRect.height) > 1.5 {
                card.setFrame(newCardRect, display: true, animate: false)
            }
        }
    }

    func nextStep() {
        if currentStepIndex < SpotlightTourStep.allCases.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex += 1
            }
            stepDidChange()
        } else {
            closeTour()
        }
    }

    func prevStep() {
        if currentStepIndex > 0 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex -= 1
            }
            stepDidChange()
        }
    }

    private func stepDidChange() {
        guard let screen = activeScreen else { return }
        
        // 1. Pre-switch live tabs & open notch for the new step beforehand (this updates currentCutoutRect)
        updateLiveUIState(for: currentStep)

        // 2. Update card frame below the updated cutout
        let newCardRect = cardRect(for: currentStep, screen: screen)
        cardWindow?.setFrame(newCardRect, display: true, animate: true)
    }

    private func cardRect(for step: SpotlightTourStep, screen: NSScreen) -> NSRect {
        let screenSize = screen.frame.size
        let screenOrigin = screen.frame.origin
        let cardWidth: CGFloat = 430
        let cardHeight: CGFloat = (step == .faceIDLock) ? 290 : 240
        let padding: CGFloat = 20

        let x = (screenSize.width - cardWidth) / 2

        let cutoutBottom: CGFloat
        if currentCutoutRect != .zero {
            cutoutBottom = currentCutoutRect.maxY
        } else {
            cutoutBottom = 210
        }
        let topY = cutoutBottom + 16
        let constrainedTopY = min(screenSize.height - cardHeight - padding, topY)

        let appKitY = screenOrigin.y + (screenSize.height - constrainedTopY - cardHeight)
        let appKitX = screenOrigin.x + x

        return NSRect(x: appKitX, y: appKitY, width: cardWidth, height: cardHeight)
    }

    private func updateLiveUIState(for step: SpotlightTourStep) {
        guard let appDelegate = (NSApp.delegate as? AppDelegate) ?? AppDelegate.shared else { return }
        let coordinator = NotchPulseViewCoordinator.shared
        coordinator.firstLaunch = false
        coordinator.alwaysShowTabs = true
        Defaults[.notchPulseShelf] = true
        Defaults[.enableClipboardManager] = true
        Defaults[.showCalendar] = true
        SharingStateManager.shared.preventNotchClose = true

        let targetVM: NotchPulseViewModel
        if Defaults[.showOnAllDisplays] {
            if let activeUUID = self.activeScreen?.displayUUID,
               let vm = appDelegate.viewModels[activeUUID] {
                targetVM = vm
            } else if let firstVM = appDelegate.viewModels.values.first {
                targetVM = firstVM
            } else {
                targetVM = appDelegate.vm
            }
        } else {
            targetVM = appDelegate.vm
        }

        // Collect all active view models so every display's notch responds synchronously
        var allVMs: [NotchPulseViewModel] = [appDelegate.vm]
        for vm in appDelegate.viewModels.values {
            if !allVMs.contains(where: { $0 === vm }) {
                allVMs.append(vm)
            }
        }

        let targetView: NotchViews
        let isFullMonth: Bool
        let customHeight: CGFloat?

        switch step {
        case .notchHover:
            targetView = .home
            isFullMonth = false
            customHeight = nil

        case .shakeToShelf:
            Defaults[.notchPulseShelf] = true
            targetView = .shelf
            isFullMonth = false
            customHeight = nil

        case .musicPlayer:
            targetView = .home
            isFullMonth = false
            customHeight = nil

        case .calendarExpand:
            Defaults[.showCalendar] = true
            targetView = .home
            isFullMonth = false
            customHeight = nil

        case .calendarFullMonth:
            Defaults[.showCalendar] = true
            targetView = .home
            isFullMonth = true
            customHeight = 240

        case .clipboardManager:
            Defaults[.enableClipboardManager] = true
            targetView = .clipboard
            isFullMonth = false
            customHeight = 250

        case .faceIDLock:
            targetView = .home
            isFullMonth = false
            customHeight = nil

        case .menuBarSettings:
            targetView = .home
            isFullMonth = false
            customHeight = nil
        }

        // 1. Smoothly switch tabs & calendar full month state
        withAnimation(.smooth(duration: 0.28)) {
            coordinator.currentView = targetView
        }
        CalendarStateViewModel.shared.isFullMonthExpanded = isFullMonth

        // 2. Open live Notch across all displays and apply target custom open height
        for vm in allVMs {
            vm.customOpenHeight = customHeight
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                vm.notchSize = openNotchSize
                vm.notchState = .open
            }
            MusicManager.shared.isUIActive = true
            MusicManager.shared.forceUpdate()
        }

        // 3. Bring Notch windows front so they are visible and interactable
        appDelegate.window?.orderFrontRegardless()
        for win in appDelegate.windows.values {
            win.orderFrontRegardless()
        }

        // 4. After opening live Notch, compute the spotlight cutout accurately
        updateCutoutRectFromLiveVM(step: step, targetVM: targetVM)
    }

    /// Compute the spotlight cutout rect by reading the live notch dimensions from `targetVM`
    /// after `open()` has been called. This ensures the highlight ring is always pixel-accurate
    /// regardless of user width/height settings or custom open height overrides.
    @MainActor
    private func updateCutoutRectFromLiveVM(step: SpotlightTourStep, targetVM: NotchPulseViewModel) {
        guard let screen = activeScreen else { return }
        let (rect, radius) = computeCutoutRect(for: step, screen: screen, targetVM: targetVM)

        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            self.currentCutoutRect = rect
            self.currentCornerRadius = radius
        }
    }

    @MainActor
    func computeCutoutRect(for step: SpotlightTourStep, screen: NSScreen, targetVM: NotchPulseViewModel) -> (CGRect, CGFloat) {
        let screenSize = screen.frame.size
        let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
        let openWidth = max(minNotchWidth, min(maxNotchWidth, CGFloat(Defaults[.notchOpenWidth])))
        
        // In standard notch mode, ContentView adds horizontal padding: 2 * 19 = 38
        let notchTotalWidth = isDynamicIsland ? openWidth : (openWidth + 38)
        
        let notchContentHeight: CGFloat
        if step == .calendarFullMonth {
            notchContentHeight = 240
        } else if step == .clipboardManager {
            notchContentHeight = 250
        } else {
            notchContentHeight = targetVM.customOpenHeight ?? openNotchSize.height
        }
        
        let notchTotalHeight = notchContentHeight + 8 // 8pt bottom padding in ContentView
        
        if isDynamicIsland {
            let topOffset = Defaults[.dynamicIslandTopOffset]
            let pad: CGFloat = 8
            let width = notchTotalWidth + pad * 2
            let height = notchTotalHeight + pad * 2
            let x = (screenSize.width - width) / 2
            let y = topOffset - pad
            return (CGRect(x: x, y: y, width: width, height: height), 26 + pad)
        } else {
            let pad: CGFloat = 8
            let width = notchTotalWidth + pad * 2
            let topExtension: CGFloat = 18
            let height = notchTotalHeight + pad + topExtension
            let x = (screenSize.width - width) / 2
            let y = -topExtension
            return (CGRect(x: x, y: y, width: width, height: height), 28)
        }
    }

    func hideTour() {
        backdropWindow?.orderOut(nil)
        cardWindow?.orderOut(nil)
    }

    func unhideTour() {
        guard isActive else { return }
        backdropWindow?.orderFrontRegardless()
        cardWindow?.orderFrontRegardless()
    }

    func startFaceIDSetupFromTour(completion: @escaping () -> Void) {
        hideTour()

        // Start enrollment flow. When user completes it or closes/cancels it,
        // FaceIDEnrollmentController invokes onDismiss, which unhides the tour and advances cleanly to next step!
        FaceIDEnrollmentController.startEnrollmentOnly { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                self.unhideTour()
                completion()
            }
        }
    }

    func closeTour() {
        if let obs = faceIDPhaseObserver {
            NotificationCenter.default.removeObserver(obs)
            faceIDPhaseObserver = nil
        }
        isActive = false
        backdropWindow?.orderOut(nil)
        backdropWindow = nil

        cardWindow?.orderOut(nil)
        cardWindow = nil

        let coordinator = NotchPulseViewCoordinator.shared
        coordinator.alwaysShowTabs = false
        coordinator.firstLaunch = false
        coordinator.currentView = .home
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        SharingStateManager.shared.preventNotchClose = false

        // Keep the active Notch OPEN after closing tour so user can start using it immediately!
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let targetVM: NotchPulseViewModel
        if let activeUUID = self.activeScreen?.displayUUID,
           let vm = appDelegate.viewModels[activeUUID] {
            targetVM = vm
        } else {
            targetVM = appDelegate.vm
        }
        targetVM.customOpenHeight = nil
        targetVM.open()
    }
}
