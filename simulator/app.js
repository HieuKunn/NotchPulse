// State Management
const state = {
  notchOpen: false,
  activeTab: 'stats', // default to stats so user sees it right away!
  musicPlaying: true,
  settingsOpen: false,
  activeSettingsTab: 'systemMonitor',
  enableSystemMonitor: true,
  showProcesses: true,
  // Hardware metrics
  cpu: 14.5,
  cpuUser: 9.8,
  cpuSys: 4.7,
  cpuIdle: 85.5,
  cpuHistory: [8, 12, 10, 15, 14, 18, 16, 22, 19, 14, 15, 12, 17, 14, 16, 13, 15, 19, 14],
  ramUsed: 10.34,
  ramTotal: 16.0,
  ramApp: 6.8,
  ramWired: 2.1,
  ramComp: 1.44,
  ramFree: 5.66,
  ramHistory: [62, 63, 63, 64, 64, 65, 64, 64, 64, 65, 64, 65, 64, 64, 65],
  gpu: 8.2,
  gpuHistory: [4, 6, 8, 7, 12, 9, 8, 14, 10, 8, 9, 7, 11, 8, 9],
  topCpuProc: { name: 'WindowServer', val: '4.8%' },
  topRamProc: { name: 'Google Chrome', val: '1.8 GB' }
};

// DOM Elements
const notch = document.getElementById('notchPulse');
const tabsCapsule = document.getElementById('tabsCapsule');
const statsTabBtn = document.getElementById('tabBtnStats');
const settingsOverlay = document.getElementById('settingsOverlay');
const sparkleMenu = document.getElementById('sparkleMenu');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  setupEventListeners();
  startHardwareSimulation();
  renderSparklines();
  switchTab(state.activeTab);
});

// Toggle Notch Open/Closed
function toggleNotch(forceState) {
  state.notchOpen = typeof forceState === 'boolean' ? forceState : !state.notchOpen;
  if (state.notchOpen) {
    notch.classList.add('open');
  } else {
    notch.classList.remove('open');
  }
}

// Switch Tabs
function switchTab(tabId) {
  state.activeTab = tabId;
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabId);
  });
  document.querySelectorAll('.tab-pane').forEach(pane => {
    pane.classList.toggle('active', pane.id === `tabPane-${tabId}`);
  });
}

// Toggle Settings Window
function toggleSettings(forceState) {
  state.settingsOpen = typeof forceState === 'boolean' ? forceState : !state.settingsOpen;
  if (state.settingsOpen) {
    settingsOverlay.classList.add('show');
    sparkleMenu.classList.remove('show');
  } else {
    settingsOverlay.classList.remove('show');
  }
}

// Switch Settings Tab
function switchSettingsTab(tabKey) {
  state.activeSettingsTab = tabKey;
  document.querySelectorAll('.sidebar-item').forEach(item => {
    item.classList.toggle('active', item.dataset.tab === tabKey);
  });

  const detailTitle = document.getElementById('settingsDetailTitle');
  const systemMonitorContent = document.getElementById('settingsSystemMonitorContent');
  const genericContent = document.getElementById('settingsGenericContent');

  if (tabKey === 'systemMonitor') {
    detailTitle.textContent = 'System Monitor';
    systemMonitorContent.style.display = 'block';
    genericContent.style.display = 'none';
  } else if (tabKey === 'hud') {
    detailTitle.textContent = 'HUDs';
    systemMonitorContent.style.display = 'none';
    genericContent.style.display = 'block';
    document.getElementById('genericDesc').textContent = 'Configure custom on-screen display (HUD) replacements for volume, display brightness, and keyboard backlight.';
  } else {
    detailTitle.textContent = tabKey.charAt(0).toUpperCase() + tabKey.slice(1);
    systemMonitorContent.style.display = 'none';
    genericContent.style.display = 'block';
    document.getElementById('genericDesc').textContent = `Configuration options for ${tabKey}.`;
  }
}

// Setup Event Listeners
function setupEventListeners() {
  // Hover Notch to expand
  let hoverTimeout;
  notch.addEventListener('mouseenter', () => {
    hoverTimeout = setTimeout(() => {
      toggleNotch(true);
    }, 120);
  });

  notch.addEventListener('mouseleave', () => {
    clearTimeout(hoverTimeout);
  });

  // Tab Buttons
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      switchTab(btn.dataset.tab);
    });
  });

  // Sparkle Icon in Menu Bar
  const sparkleBtn = document.getElementById('sparkleMenuBtn');
  sparkleBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    sparkleMenu.classList.toggle('show');
  });

  document.addEventListener('click', (e) => {
    if (!sparkleMenu.contains(e.target) && e.target !== sparkleBtn) {
      sparkleMenu.classList.remove('show');
    }
  });

  // Calendar Date Item Selection
  document.querySelectorAll('.date-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.stopPropagation();
      document.querySelectorAll('.date-item').forEach(d => d.classList.remove('active'));
      item.classList.add('active');
    });
  });

  // Settings Sidebar Items
  document.querySelectorAll('.sidebar-item').forEach(item => {
    item.addEventListener('click', () => {
      switchSettingsTab(item.dataset.tab);
    });
  });

  // System Monitor Main Switch
  const toggleMonitorCheckbox = document.getElementById('toggleEnableMonitor');
  toggleMonitorCheckbox.addEventListener('change', (e) => {
    state.enableSystemMonitor = e.target.checked;
    statsTabBtn.style.display = state.enableSystemMonitor ? 'flex' : 'none';
    if (!state.enableSystemMonitor && state.activeTab === 'stats') {
      switchTab('home');
    }
  });

  // Hotkeys
  document.addEventListener('keydown', (e) => {
    // Cmd + Shift + I -> Toggle Notch
    if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.code === 'KeyI') {
      e.preventDefault();
      toggleNotch();
    }
    // Cmd + , -> Toggle Settings
    if ((e.metaKey || e.ctrlKey) && e.key === ',') {
      e.preventDefault();
      toggleSettings();
    }
    // Escape -> Close Settings
    if (e.key === 'Escape' && state.settingsOpen) {
      toggleSettings(false);
    }
  });
}

// Real-time Simulation Engine
function startHardwareSimulation() {
  setInterval(() => {
    // CPU fluctuation
    const cpuDelta = (Math.random() - 0.48) * 4;
    state.cpu = Math.max(5, Math.min(95, state.cpu + cpuDelta));
    state.cpuUser = state.cpu * 0.72;
    state.cpuSys = state.cpu * 0.28;
    state.cpuIdle = 100 - state.cpu;
    state.cpuHistory.push(state.cpu);
    if (state.cpuHistory.length > 22) state.cpuHistory.shift();

    // RAM fluctuation (subtle)
    const ramDelta = (Math.random() - 0.5) * 0.05;
    state.ramUsed = Math.max(8.5, Math.min(15.2, state.ramUsed + ramDelta));
    const ramPercent = (state.ramUsed / state.ramTotal) * 100;
    state.ramHistory.push(ramPercent);
    if (state.ramHistory.length > 22) state.ramHistory.shift();

    // GPU fluctuation
    const gpuDelta = (Math.random() - 0.49) * 3;
    state.gpu = Math.max(2, Math.min(85, state.gpu + gpuDelta));
    state.gpuHistory.push(state.gpu);
    if (state.gpuHistory.length > 22) state.gpuHistory.shift();

    // Update UI Elements
    updateUIData();
    renderSparklines();
  }, 1400);
}

// Update UI Values
function updateUIData() {
  // CPU
  document.getElementById('statCpuVal').textContent = `${Math.round(state.cpu)}%`;
  document.getElementById('segUser').style.width = `${state.cpuUser}%`;
  document.getElementById('segSys').style.width = `${state.cpuSys}%`;
  document.getElementById('lblUser').textContent = `U:${Math.round(state.cpuUser)}%`;
  document.getElementById('lblSys').textContent = `S:${Math.round(state.cpuSys)}%`;
  document.getElementById('lblIdle').textContent = `I:${Math.round(state.cpuIdle)}%`;

  // RAM
  document.getElementById('statRamVal').textContent = `${state.ramUsed.toFixed(1)} GB`;
  const total = state.ramTotal;
  document.getElementById('segApp').style.width = `${(state.ramApp / total) * 100}%`;
  document.getElementById('segWired').style.width = `${(state.ramWired / total) * 100}%`;
  document.getElementById('segComp').style.width = `${(state.ramComp / total) * 100}%`;

  // GPU
  document.getElementById('statGpuVal').textContent = `${Math.round(state.gpu)}%`;
  document.getElementById('segGpu').style.width = `${Math.max(4, state.gpu)}%`;

  // Settings Live Preview
  document.getElementById('previewCpu').textContent = `${Math.round(state.cpu)}%`;
  document.getElementById('previewRam').textContent = `${state.ramUsed.toFixed(1)} / 16 GB`;
  document.getElementById('previewGpu').textContent = `${Math.round(state.gpu)}%`;
}

// Draw Smooth SVG Sparkline Paths
function renderSparklines() {
  drawSparkline('cpuSparkline', state.cpuHistory, '#3b82f6', 100);
  drawSparkline('ramSparkline', state.ramHistory, '#22c55e', 100);
  drawSparkline('gpuSparkline', state.gpuHistory, '#c084fc', 100);
}

function drawSparkline(svgId, data, color, maxVal) {
  const svg = document.getElementById(svgId);
  if (!svg) return;
  const w = 180;
  const h = 28;
  const count = data.length;
  const step = w / (count - 1);

  let pathD = '';
  let fillD = `M 0 ${h} `;

  data.forEach((val, i) => {
    const x = i * step;
    const clamped = Math.max(0, Math.min(maxVal, val));
    const y = h - (clamped / maxVal) * (h - 6) - 3;

    if (i === 0) {
      pathD += `M ${x} ${y} `;
      fillD += `L ${x} ${y} `;
    } else {
      pathD += `L ${x} ${y} `;
      fillD += `L ${x} ${y} `;
    }
  });

  fillD += `L ${w} ${h} Z`;

  svg.innerHTML = `
    <defs>
      <linearGradient id="grad-${svgId}" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${color}" stop-opacity="0.35" />
        <stop offset="100%" stop-color="${color}" stop-opacity="0.02" />
      </linearGradient>
    </defs>
    <path d="${fillD}" fill="url(#grad-${svgId})" />
    <path d="${pathD}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
  `;
}

// Quick Trigger Actions
function triggerCpuSpike() {
  state.cpu = 88.5;
  state.gpu = 74.0;
  state.topCpuProc = { name: 'Final Cut Pro', val: '64.2%' };
  document.getElementById('topCpuProcName').textContent = 'Final Cut Pro';
  document.getElementById('topCpuProcVal').textContent = '64.2%';
  updateUIData();
  renderSparklines();
  if (!state.notchOpen) toggleNotch(true);
  switchTab('stats');
}

function toggleMusicPlayback() {
  state.musicPlaying = !state.musicPlaying;
  const sneak = document.getElementById('musicSneakPreview');
  const waves = document.querySelectorAll('.wave-bar');
  if (state.musicPlaying) {
    sneak.style.display = 'flex';
    waves.forEach(w => w.style.animationPlayState = 'running');
  } else {
    sneak.style.display = 'none';
    waves.forEach(w => w.style.animationPlayState = 'paused');
  }
}

// Toggle Bezel Mode (Offsets Notch so it's NEVER obscured by browser bars or physical Mac notches)
function toggleBezelMode() {
  const isBezel = document.body.classList.toggle('bezel-mode');
  const label = document.getElementById('bezelModeLabel');
  if (label) {
    label.textContent = isBezel ? 'Chế độ Sát mép màn hình' : 'Hạ Notch xuống (Tránh bị che)';
  }
}

// Camera Preview Toggle Simulator (Instant zero-delay mirror)
function toggleCameraPreview() {
  const card = document.getElementById('cameraMirrorCard');
  if (!card) return;
  const isHidden = card.style.display === 'none' || !card.style.display;
  if (isHidden) {
    switchTab('home');
    card.style.display = 'flex';
  } else {
    card.style.display = 'none';
  }
}

// HUD Brightness & Display Target Simulator
let hudTimeout = null;
let currentDisplayMode = 'retina'; // 'retina' | 'external'
let retinaBrightness = 65;
let externalBrightness = 80;

function triggerBrightnessHUD() {
  const notch = document.getElementById('notchPulse');
  const hud = document.getElementById('hudSneakPreview');
  const music = document.getElementById('musicSneakPreview');
  if (!hud || !notch) return;

  // Make sure notch is closed for HUD sneak peek
  if (notch.classList.contains('open')) {
    toggleNotch(false);
  }

  music.style.display = 'none';
  hud.style.display = 'flex';
  updateHudDisplayUI();

  clearTimeout(hudTimeout);
  hudTimeout = setTimeout(() => {
    hud.style.display = 'none';
    if (state.musicPlaying) {
      music.style.display = 'flex';
    }
  }, 2500);
}

function toggleHudDisplay(event) {
  if (event) event.stopPropagation();
  currentDisplayMode = currentDisplayMode === 'retina' ? 'external' : 'retina';
  updateHudDisplayUI();
  
  // Refresh HUD timer
  clearTimeout(hudTimeout);
  hudTimeout = setTimeout(() => {
    const hud = document.getElementById('hudSneakPreview');
    const music = document.getElementById('musicSneakPreview');
    if (hud) hud.style.display = 'none';
    if (state.musicPlaying && music) music.style.display = 'flex';
  }, 2500);
}

function updateHudDisplayUI() {
  const icon = document.getElementById('hudIcon');
  const title = document.getElementById('hudTitle');
  const fill = document.getElementById('hudSliderFill');
  const pct = document.getElementById('hudPercent');
  if (!icon || !title || !fill || !pct) return;

  if (currentDisplayMode === 'retina') {
    icon.className = 'fa-solid fa-sun';
    title.textContent = 'Retina';
    fill.style.width = `${retinaBrightness}%`;
    pct.textContent = `${retinaBrightness}%`;
  } else {
    icon.className = 'fa-solid fa-desktop';
    title.textContent = 'Màn phụ';
    fill.style.width = `${externalBrightness}%`;
    pct.textContent = `${externalBrightness}%`;
  }
}

// Lock Screen Simulation Toggle
function toggleLockScreen() {
  const overlay = document.getElementById('lockScreenOverlay');
  if (overlay) {
    if (overlay.classList.contains('active')) {
      overlay.classList.remove('active');
    } else {
      overlay.classList.add('active');
    }
  }
}

// Face ID Style Toggle (Pop-down vs Inline)
let currentFaceIDStyle = 'pop-down';
function toggleFaceIDStyle() {
  const container = document.getElementById('lockFaceIDNotch');
  const label = document.getElementById('faceIDStyleLabel');
  if (currentFaceIDStyle === 'pop-down') {
    currentFaceIDStyle = 'inline';
    if (container) {
      container.classList.remove('pop-down');
      container.classList.add('inline');
    }
    if (label) label.textContent = 'Kiểu FaceID: Inline';
  } else {
    currentFaceIDStyle = 'pop-down';
    if (container) {
      container.classList.remove('inline');
      container.classList.add('pop-down');
    }
    if (label) label.textContent = 'Kiểu FaceID: Pop-down';
  }
}
