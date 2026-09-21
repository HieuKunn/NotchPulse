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
// Localization Dictionary (EN / VI)
// =============================================================================

const i18nData = {
  en: {
    // Navigation
    "nav.features": "Features",
    "nav.demo": "Live Demo",
    "nav.reviews": "Reviews",
    "nav.creator": "Creator",
    "nav.download": "Download",
    "nav.get": "Get App",

    // Hero
    "hero.badge": "NotchPulse v4.5 Released",
    "hero.title": "MacBook Notch, Reimagined.",
    "hero.subtitle": "Transform your MacBook camera notch into a fluid, 120Hz ProMotion interactive Dynamic Island. Native Apple Silicon performance with Biometric Face ID, real-time lyrics, and smart hardware HUDs.",
    "hero.downloadBtn": "Download DMG (v4.5)",

    // Chips
    "chip.faceidTitle": "Face ID Ready",
    "chip.faceidSub": "Instant biometric unlock",
    "chip.lyricsTitle": "Live Synced Lyrics",
    "chip.lyricsSub": "Spotify & Apple Music",

    // Demo Controls & Notch
    "demo.modeNotch": "MacBook Notch",
    "demo.modeIsland": "Dynamic Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Music & Lyrics",
    "demo.pillBattery": "98W MagSafe",
    "demo.pillShelf": "Notch Shelf",
    "demo.hint": "Click or hover over the notch above to trigger 120Hz fluid expansion!",
    "notch.idle": "NotchPulse Active",
    "notch.faceIdScanned": "Face ID Verified",
    "notch.faceIdPrompt": "Mac unlocked seamlessly via front camera",

    // Bento Features Section
    "features.tag": "Engineered for macOS",
    "features.title": "Next-Level Bento Architecture",
    "features.subtitle": "Built natively in Swift with 0% CPU overhead at idle. Experience smooth 120Hz ProMotion animations, biometric conveniences, and smart desktop tools.",
    
    "feat1.title": "Biometric Face ID Recognition",
    "feat1.desc": "Brings iOS-grade facial recognition to your Mac. Continuously senses your presence, previews camera status smoothly, and unlocks protected apps with privacy-first on-device Apple Vision processing.",
    "bento.faceidVerified": "Neural Face Mesh Active",

    "feat2.title": "120Hz ProMotion Dual Mode",
    "feat2.desc": "Fluidly morphs between native MacBook Notch profile and a centered floating Dynamic Island on external Studio Displays.",

    "feat3.title": "Live Synced Karaoke Lyrics",
    "feat3.desc": "Live word-by-word streaming lyrics for Spotify and Apple Music directly over the notch. Scrub tracks, seek timestamps, or expand into fullscreen lyric mode with vibrant album artwork.",

    "feat4.title": "Notch Shelf & Quick Drop",
    "feat4.desc": "Drag files, links, or screenshots directly into the notch bezel to hold them temporarily across workspaces and apps.",

    "feat5.title": "Hardware DDC External Display HUD",
    "feat5.desc": "Control genuine third-party monitor hardware brightness and audio volume via DDC/CI with native Apple keyboard shortcuts.",

    "feat6.title": "Smart Power & 140W MagSafe HUD",
    "feat6.desc": "Plugging in MagSafe or USB-C reveals live charging wattage, estimated time to 100%, and battery health cycle telemetry.",

    // Reviews Section
    "reviews.tag": "Global Community",
    "reviews.title": "Loved by Developers Worldwide",
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
    "install.subtitle": "Compatible with macOS 14.0+ Sonoma and macOS 15 Sequoia. Optimized for Apple Silicon M1/M2/M3/M4 & Intel Macs.",
    "install.btnDmg": "Download NotchPulse-4.5.dmg",

    // Toast
    "toast.copied": "Homebrew command copied to clipboard!"
  },

  vi: {
    // Navigation
    "nav.features": "Tính Năng Bento",
    "nav.demo": "Demo Trực Tiếp",
    "nav.reviews": "Đánh Giá Quốc Tế",
    "nav.creator": "Tác Giả",
    "nav.download": "Tải Xuống",
    "nav.get": "Tải Ngay",

    // Hero
    "hero.badge": "Đã ra mắt NotchPulse v4.5",
    "hero.title": "Tai Thỏ MacBook, Tái Định Nghĩa.",
    "hero.subtitle": "Biến phần khuyết camera trên MacBook thành Dynamic Island tương tác mượt mà 120Hz ProMotion. Tối ưu hoàn hảo cho chip Apple Silicon với nhận diện Face ID, lời bài hát karaoke thời gian thực và bảng điều khiển HUD thông minh.",
    "hero.downloadBtn": "Tải file DMG (v4.5)",

    // Chips
    "chip.faceidTitle": "Face ID Sẵn Sàng",
    "chip.faceidSub": "Mở khóa khuôn mặt tức thì",
    "chip.lyricsTitle": "Lời Nhạc Trực Tiếp",
    "chip.lyricsSub": "Spotify & Apple Music",

    // Demo Controls & Notch
    "demo.modeNotch": "Tai Thỏ MacBook",
    "demo.modeIsland": "Đảo Động Island",
    "demo.pillFaceID": "Face ID",
    "demo.pillMusic": "Nhạc & Lời Bài Hát",
    "demo.pillBattery": "Sạc MagSafe 98W",
    "demo.pillShelf": "Ngăn Chứa Notch",
    "demo.hint": "Nhấp chuột hoặc rê vào tai thỏ phía trên để trải nghiệm mở rộng 120Hz siêu mượt!",
    "notch.idle": "NotchPulse Đang Hoạt Động",
    "notch.faceIdScanned": "Đã Xác Thực Face ID",
    "notch.faceIdPrompt": "Mở khoá máy Mac an toàn qua camera trước",

    // Bento Features Section
    "features.tag": "Tối Ưu Riêng Cho macOS",
    "features.title": "Kiến Trúc Bento Đẳng Cấp",
    "features.subtitle": "Viết bằng Swift thuần túy, 0% CPU khi chạy nền. Tận hưởng hoạt ảnh 120Hz ProMotion, bảo mật sinh trắc học và công cụ làm việc thông minh.",
    
    "feat1.title": "Mở Khoá Face ID Sinh Trắc Học",
    "feat1.desc": "Mang trải nghiệm nhận diện khuôn mặt chuẩn iPhone lên máy Mac. Tự động cảm biến hiện diện, xem trước camera mượt mà và mở khóa ứng dụng an toàn với Apple Vision ngay trên thiết bị.",
    "bento.faceidVerified": "Mô Hình Lưới Face Mesh Kích Hoạt",

    "feat2.title": "Chế Độ Kép 120Hz Notch & Island",
    "feat2.desc": "Tự động chuyển đổi linh hoạt giữa màn hình tai thỏ MacBook Pro và màn hình ngoài Studio Display ở tần số 120Hz ProMotion.",

    "feat3.title": "Lời Nhạc Đồng Bộ Karaoke Trực Tiếp",
    "feat3.desc": "Hiển thị lời bài hát karaoke chạy từng chữ theo thời gian thực trên tai thỏ cho Spotify và Apple Music. Rê chuột để tua nhạc, tạm dừng hoặc xem ảnh bìa album siêu nét.",

    "feat4.title": "Ngăn Kéo Notch Shelf & Thả Nhanh",
    "feat4.desc": "Biến phần khuyết tai thỏ thành nơi lưu tạm tài liệu thông minh. Kéo thả file, ảnh, đường link hoặc đoạn mã lên đỉnh màn hình để chuyển đổi nhanh giữa các app.",

    "feat5.title": "Điều Khiển Màn Hình Ngoài DDC HUD",
    "feat5.desc": "Can thiệp phần cứng DDC/CI trực tiếp cho màn hình rời. Tăng giảm độ sáng thật, độ tương phản và âm lượng bằng phím tắt bàn phím tiện lợi.",

    "feat6.title": "Bảng Theo Dõi Pin & Sạc MagSafe 140W",
    "feat6.desc": "Khi cắm sạc MagSafe hoặc USB-C, tai thỏ lập tức mở rộng thông báo công suất sạc watt thời gian thực, thời gian sạc đầy dự kiến và số chu kỳ sức khỏe pin.",

    // Reviews Section
    "reviews.tag": "Cộng Đồng Toàn Cầu",
    "reviews.title": "Được Kỹ Sư Toàn Cầu Đánh Giá Cao",
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
    "install.subtitle": "Tương thích hoàn toàn với macOS 14.0+ Sonoma và macOS 15 Sequoia. Tối ưu cho chip Apple Silicon M1/M2/M3/M4 và chip Intel.",
    "install.btnDmg": "Tải về NotchPulse-4.5.dmg",

    // Toast
    "toast.copied": "Đã sao chép lệnh Homebrew vào bộ nhớ tạm!"
  }
};

// =============================================================================
// App State & Initialization
// =============================================================================

let currentLang = localStorage.getItem("notchpulse_lang") || (navigator.language.startsWith("vi") ? "vi" : "en");
let notchMode = "notch"; // 'notch' or 'island'
let currentAction = "faceid"; // 'faceid', 'music', 'battery', 'shelf'

document.addEventListener("DOMContentLoaded", () => {
  initLanguage();
  initScrollFadeIn();
  initParallaxAndTilt();
  initNotchSimulator();
  initReviewsFilter();
  initCopyActions();
});

// =============================================================================
// 1. Scroll-Driven Fade-In Animations (IntersectionObserver)
// =============================================================================

function initScrollFadeIn() {
  const elements = document.querySelectorAll(".fade-in-section");
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
      }
    });
  }, {
    threshold: 0.1,
    rootMargin: "0px 0px -40px 0px"
  });

  elements.forEach((el) => {
    observer.observe(el);
  });
}

// =============================================================================
// 2. Language Switcher (EN / VI)
// =============================================================================

function initLanguage() {
  const langToggle = document.getElementById("langToggle");
  applyLanguage(currentLang);

  if (langToggle) {
    langToggle.addEventListener("click", () => {
      currentLang = currentLang === "en" ? "vi" : "en";
      localStorage.setItem("notchpulse_lang", currentLang);
      applyLanguage(currentLang);
    });
  }
}

function applyLanguage(lang) {
  const langLabel = document.getElementById("langLabel");
  const langFlag = document.getElementById("langFlag");

  if (langLabel) langLabel.textContent = lang.toUpperCase();
  if (langFlag) langFlag.textContent = lang === "vi" ? "🇻🇳" : "🇺🇸";

  const dict = i18nData[lang] || i18nData.en;
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    if (dict[key]) {
      el.textContent = dict[key];
    }
  });

  renderNotchContent();
}

// =============================================================================
// 3. 3D Mouse Perspective Tilt & Parallax
// =============================================================================

function initParallaxAndTilt() {
  const deviceFrame = document.getElementById("deviceFrame");
  const chipFaceId = document.getElementById("chipFaceId");
  const chipLyrics = document.getElementById("chipLyrics");
  const ambientGlow = document.getElementById("ambientGlow");

  if (!deviceFrame) return;

  window.addEventListener("mousemove", (e) => {
    const rect = deviceFrame.getBoundingClientRect();
    const frameCenterX = rect.left + rect.width / 2;
    const frameCenterY = rect.top + rect.height / 2;

    const deltaX = (e.clientX - frameCenterX) / (window.innerWidth / 2);
    const deltaY = (e.clientY - frameCenterY) / (window.innerHeight / 2);

    const rotX = Math.max(-10, Math.min(10, -deltaY * 12));
    const rotY = Math.max(-10, Math.min(10, deltaX * 12));

    deviceFrame.style.transform = `perspective(1200px) rotateX(${rotX}deg) rotateY(${rotY}deg)`;

    if (chipFaceId) {
      chipFaceId.style.transform = `translate3d(${-rotY * 2.5}px, ${-rotX * 2.5}px, 40px)`;
    }
    if (chipLyrics) {
      chipLyrics.style.transform = `translate3d(${rotY * 2.5}px, ${rotX * 2.5}px, 40px)`;
    }
  });

  window.addEventListener("mouseleave", () => {
    deviceFrame.style.transform = "perspective(1200px) rotateX(0deg) rotateY(0deg)";
    if (chipFaceId) chipFaceId.style.transform = "translate3d(0, 0, 0)";
    if (chipLyrics) chipLyrics.style.transform = "translate3d(0, 0, 0)";
  });

  window.addEventListener("scroll", () => {
    const scrollY = window.scrollY;
    if (ambientGlow) {
      ambientGlow.style.transform = `translateY(${scrollY * 0.25}px)`;
    }
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

  actionPills.forEach(({ el, action }) => {
    if (el) {
      el.addEventListener("click", () => {
        actionPills.forEach((p) => p.el.classList.remove("active"));
        el.classList.add("active");
        currentAction = action;
        notch.classList.add("expanded");
        renderNotchContent();
      });
    }
  });

  if (notch) {
    notch.addEventListener("click", () => {
      notch.classList.toggle("expanded");
      renderNotchContent();
    });
  }
}

function renderNotchContent() {
  const content = document.getElementById("notchExpandedContent");
  const compactIcon = document.getElementById("compactIcon");
  const compactText = document.getElementById("compactText");
  const isVi = currentLang === "vi";

  if (!content) return;

  if (currentAction === "faceid") {
    if (compactIcon) compactIcon.textContent = "👤";
    if (compactText) compactText.textContent = isVi ? "Đã quét Face ID" : "Face ID Verified";

    content.innerHTML = `
      <div class="faceid-scanner-anim">🎯</div>
      <div style="font-weight: 700; font-size: 1.05rem; color: #fff;">
        ${isVi ? "Xác Thực Face ID Thành Công" : "Face ID Verified"}
      </div>
      <div style="font-size: 0.8rem; color: #94a3b8; margin-top: 4px;">
        ${isVi ? "Mở khóa an toàn với Apple Vision" : "Apple Vision on-device biometric check"}
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
      <div style="font-size: 0.88rem; font-weight: 600; color: #38bdf8; background: rgba(56, 189, 248, 0.12); padding: 6px 14px; border-radius: 9999px; border: 1px solid rgba(56, 189, 248, 0.3);">
        🎤 "${isVi ? "I do the same thing I told you that I never would..." : "I do the same thing I told you that I never would..."}"
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
        ${isVi ? "Dự kiến đầy trong 18 phút • Sức khỏe pin: 100%" : "Full in 18 minutes • Battery Health: 100%"}
      </div>
    `;
  } else if (currentAction === "shelf") {
    if (compactIcon) compactIcon.textContent = "📁";
    if (compactText) compactText.textContent = isVi ? "Ngăn Chứa: 3 Tệp" : "Shelf: 3 Items";

    content.innerHTML = `
      <div style="display: flex; gap: 12px; margin-bottom: 8px;">
        <div style="padding: 10px 14px; background: rgba(255, 255, 255, 0.1); border-radius: 12px; font-size: 0.8rem; text-align: center;">📄 proposal.pdf</div>
        <div style="padding: 10px 14px; background: rgba(255, 255, 255, 0.1); border-radius: 12px; font-size: 0.8rem; text-align: center;">🖼 mockup.png</div>
        <div style="padding: 10px 14px; background: rgba(255, 255, 255, 0.1); border-radius: 12px; font-size: 0.8rem; text-align: center;">🔗 figma.com/...</div>
      </div>
      <div style="font-size: 0.78rem; color: #94a3b8;">
        ${isVi ? "Kéo tệp vào tai thỏ để lưu tạm giữa các ứng dụng" : "Drop files into notch to stash temporarily"}
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
  const brewCommand = "brew install --cask https://raw.githubusercontent.com/HieuKunn/NotchPulse/main/Casks/notchpulse.rb";

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
