/**
 * KernelSU Mock GPS WebUI Application
 * Handles Leaflet map interaction, coordinates management, and KernelSU root bridge.
 */

(function () {
  'use strict';

  // Constants & Paths
  const MODULE_SCRIPT_PATH = '/data/adb/modules/ksu_fakegps/scripts/gps_control.sh';
  const DEFAULT_LAT = 35.6895;
  const DEFAULT_LNG = 139.6917;

  // Application State
  const state = {
    isActive: false,
    pid: 0,
    lat: DEFAULT_LAT,
    lng: DEFAULT_LNG,
    accuracy: 5.0,
    altitude: 40.0,
    jitter: true,
    bootPersist: false,
    isKsuAvailable: false,
    updateDebounceTimer: null
  };

  // DOM Elements
  const el = {
    map: document.getElementById('map'),
    btnMasterToggle: document.getElementById('btn-master-toggle'),
    textMasterToggle: document.getElementById('text-master-toggle'),
    iconMasterState: document.getElementById('icon-master-state'),
    badgeStatus: document.getElementById('badge-status'),
    badgeStatusText: document.getElementById('badge-status-text'),
    badgeDevOptions: document.getElementById('badge-dev-options'),
    pillCoords: document.getElementById('pill-coords'),
    btnCopyCoords: document.getElementById('btn-copy-coords'),
    inputLat: document.getElementById('input-lat'),
    inputLng: document.getElementById('input-lng'),
    inputAccuracy: document.getElementById('input-accuracy'),
    inputAltitude: document.getElementById('input-altitude'),
    switchJitter: document.getElementById('switch-jitter'),
    switchPersist: document.getElementById('switch-persist'),
    searchForm: document.getElementById('search-form'),
    searchInput: document.getElementById('search-input'),
    btnLocateMe: document.getElementById('btn-locate-me'),
    btnCenterPin: document.getElementById('btn-center-pin'),
    btnToggleLayer: document.getElementById('btn-toggle-layer'),
    presetsContainer: document.getElementById('presets-container'),
    btnPresetsPrev: document.getElementById('btn-presets-prev'),
    btnPresetsNext: document.getElementById('btn-presets-next'),
    telemetryToggle: document.getElementById('telemetry-toggle'),
    telemetryBody: document.getElementById('telemetry-body'),
    telemDevOpts: document.getElementById('telem-dev-opts'),
    telemMockApp: document.getElementById('telem-mock-app'),
    telemPid: document.getElementById('telem-pid'),
    telemBridge: document.getElementById('telem-bridge'),
    toastContainer: document.getElementById('toast-container')
  };

  let map = null;
  let targetMarker = null;
  let isInitialLoad = true;

  /* -------------------------------------------------------------------------- */
  /* KernelSU Root Bridge Wrapper                                               */
  /* -------------------------------------------------------------------------- */

  async function execCmd(cmd) {
    if (typeof ksu !== 'undefined' && ksu.exec) {
      try {
        state.isKsuAvailable = true;
        const res = ksu.exec(cmd);
        return (res instanceof Promise) ? await res : res;
      } catch (e) {
        return { errno: -1, stdout: '', stderr: String(e) };
      }
    } else if (window.ksu && window.ksu.exec) {
      try {
        state.isKsuAvailable = true;
        const res = window.ksu.exec(cmd);
        return (res instanceof Promise) ? await res : res;
      } catch (e) {
        return { errno: -1, stdout: '', stderr: String(e) };
      }
    }
    
    // Fallback Mock Mode for testing in desktop browser
    return mockBrowserExec(cmd);
  }

  // Simulated browser environment for preview
  function mockBrowserExec(cmd) {
    state.isKsuAvailable = false;
    console.log('[KernelSU Bridge Emulation] Executing:', cmd);
    
    if (cmd.includes('status')) {
      return {
        errno: 0,
        stdout: JSON.stringify({
          active: state.isActive,
          pid: state.isActive ? 9482 : 0,
          dev_options_enabled: "0",
          mock_location_app: "none",
          config: {
            enabled: state.isActive,
            latitude: state.lat,
            longitude: state.lng,
            accuracy: state.accuracy,
            altitude: state.altitude,
            jitter: state.jitter,
            boot_persist: state.bootPersist
          },
          status: {
            active: state.isActive,
            latitude: state.lat,
            longitude: state.lng,
            accuracy: state.accuracy,
            altitude: state.altitude
          }
        }),
        stderr: ''
      };
    }
    if (cmd.includes('start')) {
      state.isActive = true;
      state.pid = 9482;
      return { errno: 0, stdout: '{"success":true,"pid":9482}', stderr: '' };
    }
    if (cmd.includes('stop')) {
      state.isActive = false;
      state.pid = 0;
      return { errno: 0, stdout: '{"success":true}', stderr: '' };
    }
    if (cmd.includes('set')) {
      return { errno: 0, stdout: '{"success":true}', stderr: '' };
    }
    return { errno: 0, stdout: 'OK', stderr: '' };
  }

  /* -------------------------------------------------------------------------- */
  /* Toast Notification Helper                                                 */
  /* -------------------------------------------------------------------------- */

  function showToast(message, duration = 2800) {
    if (typeof ksu !== 'undefined' && ksu.toast) {
      ksu.toast(message);
    } else if (window.ksu && window.ksu.toast) {
      window.ksu.toast(message);
    }

    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    el.toastContainer.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(-10px)';
      toast.style.transition = 'all 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, duration);
  }

  /* -------------------------------------------------------------------------- */
  /* Tile Providers & Layer Switching                                          */
  /* -------------------------------------------------------------------------- */

  const TILE_PROVIDERS = {
    dark: {
      name: "Dark Canvas (Clean & Crisp)",
      url: "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
      options: { maxNativeZoom: 16, maxZoom: 19 }
    },
    satellite: {
      name: "Google Satellite / Roads",
      url: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
      options: { maxZoom: 20 }
    },
    streets: {
      name: "OpenStreetMap Streets",
      url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
      options: { maxZoom: 19 }
    }
  };

  let currentLayerKey = localStorage.getItem('ksu_tile_layer') || 'dark';
  let activeTileLayer = null;

  function applyTileLayer(key) {
    if (activeTileLayer && map) {
      map.removeLayer(activeTileLayer);
    }
    const provider = TILE_PROVIDERS[key] || TILE_PROVIDERS.dark;
    currentLayerKey = key;
    try {
      localStorage.setItem('ksu_tile_layer', key);
    } catch(e) {}
    activeTileLayer = L.tileLayer(provider.url, provider.options).addTo(map);
  }

  /* -------------------------------------------------------------------------- */
  /* Leaflet Map Setup                                                          */
  /* -------------------------------------------------------------------------- */

  function initMap() {
    map = L.map('map', {
      center: [state.lat, state.lng],
      zoom: 15,
      zoomControl: false,
      attributionControl: false
    });

    // Apply default tile layer (CartoDB Dark Matter)
    applyTileLayer(currentLayerKey);

    // Custom Glowing Radar Marker
    const radarIcon = L.divIcon({
      className: 'pulse-marker',
      html: '<div class="pulse-marker-ring"></div><div class="pulse-marker-center"></div>',
      iconSize: [24, 24],
      iconAnchor: [12, 12]
    });

    targetMarker = L.marker([state.lat, state.lng], {
      icon: radarIcon,
      draggable: true
    }).addTo(map);

    // Marker Drag Handlers
    targetMarker.on('drag', function (e) {
      const pos = e.target.getLatLng();
      updateCoordinates(pos.lat, pos.lng, false);
    });

    targetMarker.on('dragend', function (e) {
      const pos = e.target.getLatLng();
      updateCoordinates(pos.lat, pos.lng, true);
    });

    // Map Click Handler (move pin to clicked point)
    map.on('click', function (e) {
      updateCoordinates(e.latlng.lat, e.latlng.lng, true);
    });

    // Locate Me Button
    el.btnLocateMe.addEventListener('click', () => {
      if (navigator.geolocation) {
        showToast("Locating device...");
        navigator.geolocation.getCurrentPosition(
          (pos) => {
            const { latitude, longitude } = pos.coords;
            updateCoordinates(latitude, longitude, true);
            map.flyTo([latitude, longitude], 16, { duration: 1.2 });
            showToast("Centered to your location");
          },
          (err) => {
            showToast("Geolocation unavailable: " + err.message);
          },
          { enableHighAccuracy: true, timeout: 5000 }
        );
      } else {
        showToast("Geolocation not supported");
      }
    });

    // Center on Pin Button
    el.btnCenterPin.addEventListener('click', () => {
      map.flyTo([state.lat, state.lng], 16, { duration: 0.8 });
    });

    // Switch Tile Layer Button
    el.btnToggleLayer.addEventListener('click', () => {
      const keys = Object.keys(TILE_PROVIDERS);
      const nextIdx = (keys.indexOf(currentLayerKey) + 1) % keys.length;
      const nextKey = keys[nextIdx];
      applyTileLayer(nextKey);
      showToast(`Map Style: ${TILE_PROVIDERS[nextKey].name}`);
    });
  }

  /* -------------------------------------------------------------------------- */
  /* Coordinates & State Synchronization                                        */
  /* -------------------------------------------------------------------------- */

  function sanitizeNumber(val, fallback, min = -Infinity, max = Infinity) {
    const num = parseFloat(val);
    if (!Number.isFinite(num)) return fallback;
    return Math.max(min, Math.min(max, num));
  }

  function safeParseJson(str) {
    if (!str || typeof str !== 'string') return null;
    try {
      return JSON.parse(str);
    } catch (_) {}
    const firstBrace = str.indexOf('{');
    const lastBrace = str.lastIndexOf('}');
    if (firstBrace !== -1 && lastBrace > firstBrace) {
      try {
        return JSON.parse(str.substring(firstBrace, lastBrace + 1));
      } catch (_) {}
    }
    return null;
  }

  function updateCoordinates(lat, lng, syncDaemon = false) {
    state.lat = parseFloat(sanitizeNumber(lat, DEFAULT_LAT, -90, 90).toFixed(7));
    state.lng = parseFloat(sanitizeNumber(lng, DEFAULT_LNG, -180, 180).toFixed(7));

    // Update marker position if it differs
    if (targetMarker) {
      const currentPos = targetMarker.getLatLng();
      if (currentPos.lat !== state.lat || currentPos.lng !== state.lng) {
        targetMarker.setLatLng([state.lat, state.lng]);
      }
    }

    // Sync input fields
    el.inputLat.value = state.lat;
    el.inputLng.value = state.lng;

    // Sync Pill
    el.pillCoords.textContent = `${state.lat.toFixed(6)}, ${state.lng.toFixed(6)}`;

    // If active and sync requested, push updates to daemon
    if (state.isActive && syncDaemon) {
      debounceSyncToDaemon();
    }
  }

  function debounceSyncToDaemon() {
    clearTimeout(state.updateDebounceTimer);
    state.updateDebounceTimer = setTimeout(async () => {
      const safeLat = sanitizeNumber(state.lat, DEFAULT_LAT, -90, 90).toFixed(7);
      const safeLng = sanitizeNumber(state.lng, DEFAULT_LNG, -180, 180).toFixed(7);
      const safeAlt = sanitizeNumber(state.altitude, 40.0, -500, 9000).toFixed(1);
      const safeAcc = sanitizeNumber(state.accuracy, 5.0, 1, 100).toFixed(1);
      const safeJit = state.jitter ? 'true' : 'false';

      const cmd = `sh ${MODULE_SCRIPT_PATH} set ${safeLat} ${safeLng} ${safeAlt} ${safeAcc} ${safeJit}`;
      await execCmd(cmd);
      showToast(`Coordinates updated: ${safeLat}, ${safeLng}`);
    }, 300);
  }

  /* -------------------------------------------------------------------------- */
  /* UI Updates & Rendering                                                     */
  /* -------------------------------------------------------------------------- */

  function renderState() {
    if (state.isActive) {
      // Button: Active (Stop)
      el.btnMasterToggle.className = 'btn-master btn-stop';
      el.textMasterToggle.textContent = 'STOP SPOOFING';
      el.iconMasterState.innerHTML = '<rect x="6" y="6" width="12" height="12" rx="2"></rect>';

      // Badges
      el.badgeStatus.className = 'badge badge-status active';
      el.badgeStatusText.textContent = 'ACTIVE';

      // Telemetry
      el.telemPid.textContent = `Running (PID: ${state.pid || 'Active'})`;
      el.telemPid.style.color = 'var(--emerald-active)';
    } else {
      // Button: Inactive (Start)
      el.btnMasterToggle.className = 'btn-master btn-start';
      el.textMasterToggle.textContent = 'START SPOOFING';
      el.iconMasterState.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';

      // Badges
      el.badgeStatus.className = 'badge badge-status';
      el.badgeStatusText.textContent = 'IDLE';

      // Telemetry
      el.telemPid.textContent = 'Stopped';
      el.telemPid.style.color = 'var(--text-muted)';
    }

    // Bridge status
    el.telemBridge.textContent = state.isKsuAvailable 
      ? 'KernelSU Root Bridge (Connected)' 
      : 'WebUI Sandbox / Emulated Bridge';
    el.telemBridge.style.color = state.isKsuAvailable ? 'var(--cyan-hover)' : 'var(--amber-warning)';
  }

  /* -------------------------------------------------------------------------- */
  /* Event Listeners & Interactions                                             */
  /* -------------------------------------------------------------------------- */

  function setupEventListeners() {
    // Master Toggle Button
    el.btnMasterToggle.addEventListener('click', async () => {
      if (state.isActive) {
        // Stop Spoofing
        const res = await execCmd(`sh ${MODULE_SCRIPT_PATH} stop`);
        state.isActive = false;
        state.pid = 0;
        renderState();
        showToast("Mock GPS Stopped - Real location restored");
      } else {
        // Start Spoofing
        showToast("Starting Mock GPS Daemon...");
        // 1. Update config values
        const configJson = JSON.stringify({
          enabled: true,
          latitude: sanitizeNumber(state.lat, DEFAULT_LAT, -90, 90),
          longitude: sanitizeNumber(state.lng, DEFAULT_LNG, -180, 180),
          altitude: sanitizeNumber(state.altitude, 40.0, -500, 9000),
          accuracy: sanitizeNumber(state.accuracy, 5.0, 1, 100),
          jitter: !!state.jitter,
          interval: 1.0,
          boot_persist: !!state.bootPersist
        });
        await execCmd(`sh ${MODULE_SCRIPT_PATH} save-config '${configJson}'`);
        
        // 2. Launch daemon
        const res = await execCmd(`sh ${MODULE_SCRIPT_PATH} start`);
        state.isActive = true;
        renderState();
        await fetchDaemonStatus();
        showToast("Mock GPS Active! Dev Options remained OFF.");
      }
    });

    // Inputs Change (Lat / Lng)
    el.inputLat.addEventListener('change', () => {
      const val = parseFloat(el.inputLat.value);
      if (Number.isFinite(val) && val >= -90 && val <= 90) {
        updateCoordinates(val, state.lng, true);
        map.panTo([state.lat, state.lng]);
      }
    });

    el.inputLng.addEventListener('change', () => {
      const val = parseFloat(el.inputLng.value);
      if (Number.isFinite(val) && val >= -180 && val <= 180) {
        updateCoordinates(state.lat, val, true);
        map.panTo([state.lat, state.lng]);
      }
    });

    // Accuracy & Altitude
    el.inputAccuracy.addEventListener('change', () => {
      state.accuracy = sanitizeNumber(el.inputAccuracy.value, 5.0, 1, 100);
      el.inputAccuracy.value = state.accuracy;
      if (state.isActive) debounceSyncToDaemon();
    });

    el.inputAltitude.addEventListener('change', () => {
      state.altitude = sanitizeNumber(el.inputAltitude.value, 40.0, -500, 9000);
      el.inputAltitude.value = state.altitude;
      if (state.isActive) debounceSyncToDaemon();
    });

    // Switches
    el.switchJitter.addEventListener('change', () => {
      state.jitter = el.switchJitter.checked;
      if (state.isActive) debounceSyncToDaemon();
      showToast(state.jitter ? "Satellite drift enabled" : "Satellite drift disabled");
    });

    el.switchPersist.addEventListener('change', async () => {
      state.bootPersist = el.switchPersist.checked;
      const configJson = JSON.stringify({
        enabled: !!state.isActive,
        latitude: sanitizeNumber(state.lat, DEFAULT_LAT, -90, 90),
        longitude: sanitizeNumber(state.lng, DEFAULT_LNG, -180, 180),
        altitude: sanitizeNumber(state.altitude, 40.0, -500, 9000),
        accuracy: sanitizeNumber(state.accuracy, 5.0, 1, 100),
        jitter: !!state.jitter,
        interval: 1.0,
        boot_persist: !!state.bootPersist
      });
      await execCmd(`sh ${MODULE_SCRIPT_PATH} save-config '${configJson}'`);
      showToast(state.bootPersist ? "Will persist after boot" : "Boot persistence disabled");
    });

    // Preset Scroll Buttons
    if (el.btnPresetsPrev) {
      el.btnPresetsPrev.addEventListener('click', () => {
        el.presetsContainer.scrollBy({ left: -240, behavior: 'smooth' });
      });
    }

    if (el.btnPresetsNext) {
      el.btnPresetsNext.addEventListener('click', () => {
        el.presetsContainer.scrollBy({ left: 240, behavior: 'smooth' });
      });
    }

    // Horizontal Mouse Wheel Scroll for Presets
    if (el.presetsContainer) {
      el.presetsContainer.addEventListener('wheel', (e) => {
        if (e.deltaY !== 0) {
          e.preventDefault();
          el.presetsContainer.scrollLeft += e.deltaY;
        }
      }, { passive: false });

      // Mouse Drag-to-Scroll for Presets
      let isDraggingPresets = false;
      let presetsStartX = 0;
      let presetsScrollLeft = 0;
      let hasDragged = false;

      el.presetsContainer.addEventListener('mousedown', (e) => {
        isDraggingPresets = true;
        hasDragged = false;
        presetsStartX = e.pageX;
        presetsScrollLeft = el.presetsContainer.scrollLeft;
      });

      window.addEventListener('mouseup', () => {
        if (isDraggingPresets) {
          isDraggingPresets = false;
          setTimeout(() => { hasDragged = false; }, 60);
        }
      });

      window.addEventListener('mousemove', (e) => {
        if (!isDraggingPresets) return;
        const walk = (e.pageX - presetsStartX) * 1.3;
        if (Math.abs(walk) > 4) {
          hasDragged = true;
        }
        el.presetsContainer.scrollLeft = presetsScrollLeft - walk;
      });

      // Preset Chips Click Handler
      el.presetsContainer.addEventListener('click', (e) => {
        if (hasDragged) {
          hasDragged = false;
          return;
        }
        const chip = e.target.closest('.preset-chip');
        if (!chip) return;
        const lat = parseFloat(chip.dataset.lat);
        const lng = parseFloat(chip.dataset.lng);
        const name = chip.dataset.name;

        updateCoordinates(lat, lng, true);
        map.flyTo([lat, lng], 15, { duration: 1.5 });
        showToast(`Moved to ${name}`);
      });
    }

    // Search Location (Nominatim OpenStreetMap)
    el.searchForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const query = el.searchInput.value.trim();
      if (!query) return;

      showToast(`Searching for "${query}"...`);
      try {
        const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(query)}`;
        const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
        const data = await res.json();

        if (data && data.length > 0) {
          const lat = parseFloat(data[0].lat);
          const lng = parseFloat(data[0].lon);
          updateCoordinates(lat, lng, true);
          map.flyTo([lat, lng], 16, { duration: 1.2 });
          showToast(`Found: ${data[0].display_name.split(',')[0]}`);
        } else {
          showToast("Location not found. Try different keywords.");
        }
      } catch (err) {
        showToast("Search failed: Check network connection");
      }
    });

    // Copy Coordinates Button
    el.btnCopyCoords.addEventListener('click', () => {
      const text = `${state.lat}, ${state.lng}`;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(() => {
          showToast("Coordinates copied to clipboard!");
        });
      } else {
        // Fallback
        const ta = document.createElement('textarea');
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        ta.remove();
        showToast("Coordinates copied to clipboard!");
      }
    });

    // Telemetry Collapsible Accordion
    el.telemetryToggle.addEventListener('click', () => {
      el.telemetryToggle.classList.toggle('collapsed');
      el.telemetryBody.classList.toggle('hidden');
    });
  }

  /* -------------------------------------------------------------------------- */
  /* IP Geolocation Check & Network Shield                                      */
  /* -------------------------------------------------------------------------- */

  // Known country codes per region — bounding boxes for GPS-to-country matching
  const COUNTRY_BY_PRESET = [
    ['JP', [30, 46], [129, 146]],
    ['CA', [49, 84], [-141, -52]],
    ['CA', [41.7, 49], [-95, -74]], // Southern Ontario & Quebec corridor
    ['US', [24, 49], [-125, -66]],  // Contiguous US
    ['US', [51, 72], [-179, -130]], // Alaska
    ['GB', [49, 60], [-8, 2]],
    ['FR', [42, 52], [-5, 8]],
    ['IN', [8, 37], [68, 97]],
    ['AE', [22, 27], [51, 57]],
    ['SG', [1, 2], [103, 105]],
    ['AU', [-45, -10], [110, 155]],
    ['DE', [47, 56], [6, 16]],
    ['BR', [-35, 5], [-74, -34]],
    ['CN', [18, 54], [73, 136]],
    ['KR', [33, 43], [124, 132]],
    ['RU', [41, 82], [19, 180]],
    ['MX', [14, 33], [-118, -86]],
    ['IT', [36, 48], [6, 19]],
    ['ES', [36, 44], [-10, 5]],
    ['NL', [50, 54], [3, 8]],
    ['CH', [45, 48], [5, 11]],
    ['TR', [35, 43], [25, 45]],
  ];

  function guessCountryFromCoords(lat, lng) {
    for (const [code, [latRange, lngRange]] of COUNTRY_BY_PRESET) {
      if (lat >= latRange[0] && lat <= latRange[1] &&
          lng >= lngRange[0] && lng <= lngRange[1]) {
        return code;
      }
    }
    return null;
  }

  let ipCheckInProgress = false;

  async function fetchIpInfo() {
    if (ipCheckInProgress) return;
    ipCheckInProgress = true;

    const ipEl    = document.getElementById('telem-ip');
    const cityEl  = document.getElementById('telem-ip-city');
    const matchEl = document.getElementById('telem-ip-match');
    const mismatchWarn = document.getElementById('ip-mismatch-warn');
    const matchOk = document.getElementById('ip-match-ok');

    if (ipEl) ipEl.textContent = 'Checking...';
    if (cityEl) cityEl.textContent = 'Checking...';
    if (matchEl) matchEl.textContent = 'Checking...';

    const showResult = (ipAddr, city, country, countryCode) => {
      if (ipEl) { ipEl.textContent = ipAddr; ipEl.style.color = 'var(--text-secondary)'; }
      if (cityEl) { cityEl.textContent = city ? `${city}, ${country}` : country || 'Unknown'; cityEl.style.color = 'var(--text-secondary)'; }

      const spoofedCountry = guessCountryFromCoords(state.lat, state.lng);
      const isMatch = spoofedCountry && spoofedCountry === countryCode;

      if (matchEl) {
        if (!spoofedCountry) {
          matchEl.textContent = 'Unknown region — cannot compare';
          matchEl.style.color = 'var(--text-muted)';
        } else if (isMatch) {
          matchEl.textContent = `Match — both resolving to ${countryCode}`;
          matchEl.style.color = 'var(--emerald-active)';
        } else {
          matchEl.textContent = `Mismatch — IP: ${countryCode}, GPS: ${spoofedCountry}`;
          matchEl.style.color = 'var(--amber-warning)';
        }
      }
      if (mismatchWarn) mismatchWarn.style.display = (!isMatch && spoofedCountry) ? 'block' : 'none';
      if (matchOk)      matchOk.style.display = isMatch ? 'block' : 'none';
    };

    const showError = (msg) => {
      if (ipEl) ipEl.textContent = 'Unavailable';
      if (cityEl) cityEl.textContent = msg;
      if (matchEl) { matchEl.textContent = 'Check failed'; matchEl.style.color = 'var(--text-muted)'; }
    };

    try {
      // Primary path: route through root shell to avoid WebView CORS/network restrictions.
      // net_shield.sh ip-check runs wget/curl on the root process — no browser policy applies.
      if (state.isKsuAvailable) {
        const res = await execCmd(`sh ${MODULE_SCRIPT_PATH} net-shield ip-check`);
        if (res && (res.errno == 0 || res.errno === 0) && res.stdout) {
          const data = safeParseJson(res.stdout);
          if (data && data.status === 'success') {
            showResult(data.query || '?', data.city || data.regionName, data.country, data.countryCode);
            ipCheckInProgress = false;
            return;
          }
        }
      }

      // Fallback: direct browser fetch (works in desktop preview or if KSU bridge unavailable)
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 6000);
      let data = null;
      try {
        const r = await fetch(
          'https://ip-api.com/json/?fields=status,country,countryCode,regionName,city,query',
          { signal: controller.signal }
        );
        data = await r.json();
      } finally {
        clearTimeout(timer);
      }

      if (data && data.status === 'success') {
        showResult(data.query || '?', data.city || data.regionName, data.country, data.countryCode);
      } else {
        showError('Geo lookup failed');
      }
    } catch (e) {
      showError('No network / fetch blocked');
    } finally {
      ipCheckInProgress = false;
    }
  }

  async function updateNetShieldStatus(data) {
    const shieldEl = document.getElementById('telem-shield');
    const vpnEl = document.getElementById('telem-vpn');
    const wifiEl = document.getElementById('telem-wifi-scan');

    if (!data || !data.net) return;
    const net = data.net;

    if (shieldEl) {
      const shieldOn = net.shield_active === true || net.shield_active === 'true';
      shieldEl.textContent = shieldOn ? '🛡️ Active (GMS geo blocked)' : '⬜ Off';
      shieldEl.style.color = shieldOn ? 'var(--emerald-active)' : 'var(--text-muted)';
    }

    if (vpnEl && net.vpn) {
      const vpn = net.vpn;
      const vpnOn = vpn.vpn_active === true || vpn.vpn_active === 'true';
      vpnEl.textContent = vpnOn
        ? `✅ Active — ${vpn.iface} (${vpn.tunnel_ip || 'tunneled'})`
        : '❌ No VPN detected';
      vpnEl.style.color = vpnOn ? 'var(--emerald-active)' : 'var(--rose-danger)';
    }

    if (wifiEl) {
      const wifiScan = String(net.wifi_scan);
      wifiEl.textContent = wifiScan === '0' ? '✅ Disabled (suppressed)' : '⚠️ Enabled (can leak location)';
      wifiEl.style.color = wifiScan === '0' ? 'var(--emerald-active)' : 'var(--amber-warning)';
    }
  }

  async function toggleNetShield() {
    const shieldEl = document.getElementById('telem-shield');
    const currentOn = shieldEl && shieldEl.textContent.includes('Active');
    const action = currentOn ? 'off' : 'on';

    showToast(`${action === 'on' ? 'Enabling' : 'Disabling'} network shield...`);
    const cmd = `sh ${MODULE_SCRIPT_PATH} net-shield ${action}`;
    const res = await execCmd(cmd);

    // errno may be number or string depending on KernelSU bridge version — use loose equality
    if (res && res.errno == 0) {
      showToast(`Network shield ${action === 'on' ? 'enabled' : 'disabled'}`);
      await fetchDaemonStatus();
    } else if (res && res.stdout && res.stdout.includes('shield')) {
      // Script returned valid JSON even with non-zero exit — treat as success
      showToast(`Network shield ${action === 'on' ? 'enabled' : 'disabled'}`);
      await fetchDaemonStatus();
    } else {
      const errDetail = res ? (res.stderr || res.stdout || 'no output') : 'no response';
      showToast(`Shield toggle error — ${errDetail.substring(0, 60)}`);
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Daemon Polling & Sync                                                      */
  /* -------------------------------------------------------------------------- */

  let isStatusPolling = false;

  async function fetchDaemonStatus() {
    if (isStatusPolling) return;
    isStatusPolling = true;

    try {
      const res = await execCmd(`sh ${MODULE_SCRIPT_PATH} status`);
      if (res && res.stdout) {
        const data = safeParseJson(res.stdout);
        if (!data) return;
        
        state.isActive = !!data.active;
        state.pid = data.pid || 0;

        // Sync config if available
        if (data.config && typeof data.config.latitude === 'number') {
          state.lat = data.config.latitude;
          state.lng = data.config.longitude;
          state.accuracy = data.config.accuracy ?? state.accuracy;
          state.altitude = data.config.altitude ?? state.altitude;
          state.jitter = data.config.jitter ?? state.jitter;
          state.bootPersist = data.config.boot_persist ?? state.bootPersist;

          // Update UI controls
          el.inputAccuracy.value = state.accuracy;
          el.inputAltitude.value = state.altitude;
          el.switchJitter.checked = state.jitter;
          el.switchPersist.checked = state.bootPersist;

          updateCoordinates(state.lat, state.lng, false);
          if (isInitialLoad && map) {
            map.setView([state.lat, state.lng], 15);
            isInitialLoad = false;
          }
        }

        // Developer Options Status Readout
        if (data.dev_options_enabled === "0") {
          el.telemDevOpts.textContent = "Disabled (value: 0) [Safe]";
          el.telemDevOpts.className = "telemetry-val val-secure";
        } else {
          el.telemDevOpts.textContent = `Enabled (value: ${data.dev_options_enabled})`;
          el.telemDevOpts.className = "telemetry-val";
        }

        if (data.mock_location_app) {
          el.telemMockApp.textContent = data.mock_location_app === "none" ? "None (Undetected)" : data.mock_location_app;
        }

        // Update network shield / VPN status
        await updateNetShieldStatus(data);

        renderState();
      }
    } catch (e) {
      console.warn("Status poll error:", e);
    } finally {
      isStatusPolling = false;
    }
  }

  /* -------------------------------------------------------------------------- */
  /* Application Initialization                                                 */
  /* -------------------------------------------------------------------------- */

  async function init() {
    initMap();
    setupEventListeners();
    renderState();

    // IP panel accordion
    const ipToggle = document.getElementById('ip-panel-toggle');
    const ipBody = document.getElementById('ip-panel-body');
    if (ipToggle && ipBody) {
      ipToggle.addEventListener('click', () => {
        ipToggle.classList.toggle('collapsed');
        ipBody.classList.toggle('hidden');
      });
    }

    // IP check button
    const btnCheckIp = document.getElementById('btn-check-ip');
    if (btnCheckIp) {
      btnCheckIp.addEventListener('click', () => {
        fetchIpInfo();
        showToast('Checking IP geolocation...');
      });
    }

    // Shield toggle button
    const btnShieldToggle = document.getElementById('btn-shield-toggle');
    if (btnShieldToggle) {
      btnShieldToggle.addEventListener('click', toggleNetShield);
    }

    // Initial status check
    await fetchDaemonStatus();

    // Fetch IP on load (non-blocking)
    fetchIpInfo();

    // Periodic telemetry refresh every 4 seconds
    setInterval(fetchDaemonStatus, 4000);

    // IP re-check when location changes (debounced 3s)
    let ipRecheckTimer = null;
    const origUpdateCoords = updateCoordinates;
    // Re-check IP match whenever spoofed location changes significantly
    setInterval(() => {
      const shieldEl = document.getElementById('telem-ip-match');
      if (shieldEl && shieldEl.textContent === '') fetchIpInfo();
    }, 30000);
  }

  // Launch when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
