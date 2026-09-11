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
    targetApps: [],
    userEditingCoords: false,
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
    searchForm: document.getElementById('search-form'),
    searchInput: document.getElementById('search-input'),
    btnLocateMe: document.getElementById('btn-locate-me'),
    btnCenterPin: document.getElementById('btn-center-pin'),
    btnToggleLayer: document.getElementById('btn-toggle-layer'),
    presetsContainer: document.getElementById('presets-container'),
    btnPresetsPrev: document.getElementById('btn-presets-prev'),
    btnPresetsNext: document.getElementById('btn-presets-next'),
    appsToggle: document.getElementById('apps-panel-toggle'),
    appsBody: document.getElementById('apps-panel-body'),
    badgeAppsCount: document.getElementById('badge-apps-count'),
    formAddApp: document.getElementById('form-add-app'),
    inputAppPkg: document.getElementById('input-app-pkg'),
    targetAppsContainer: document.getElementById('target-apps-container'),
    btnEvictNow: document.getElementById('btn-evict-now'),
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
    
    if (state.targetApps.length === 0) {
      state.targetApps = ['com.google.android.apps.maps'];
    }

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
            boot_persist: state.bootPersist,
            target_apps: state.targetApps
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
    if (cmd.includes('persist')) {
      return { errno: 0, stdout: '{"success":true}', stderr: '' };
    }
    if (cmd.includes('add-app')) {
      const match = cmd.match(/add-app\s+([a-zA-Z0-9_\.]+)/);
      if (match && !state.targetApps.includes(match[1])) {
        state.targetApps.push(match[1]);
      }
      return { errno: 0, stdout: JSON.stringify({ success: true, app: match ? match[1] : '' }), stderr: '' };
    }
    if (cmd.includes('remove-app')) {
      const match = cmd.match(/remove-app\s+([a-zA-Z0-9_\.]+)/);
      if (match) {
        state.targetApps = state.targetApps.filter(a => a !== match[1]);
      }
      return { errno: 0, stdout: JSON.stringify({ success: true, app: match ? match[1] : '' }), stderr: '' };
    }
    if (cmd.includes('evict-apps')) {
      return { errno: 0, stdout: '{"success":true,"message":"Target apps evicted"}', stderr: '' };
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

    // Sync to daemon and config whenever requested
    if (syncDaemon) {
      state.userEditingCoords = true;
      debounceSyncToDaemon();
    }
  }

  function debounceSyncToDaemon() {
    clearTimeout(state.updateDebounceTimer);
    state.updateDebounceTimer = setTimeout(async () => {
      const safeLat = sanitizeNumber(state.lat, DEFAULT_LAT, -90, 90).toFixed(7);
      const safeLng = sanitizeNumber(state.lng, DEFAULT_LNG, -180, 180).toFixed(7);
      const safeAcc = sanitizeNumber(state.accuracy, 5.0, 1, 100).toFixed(1);

      const cmd = `sh ${MODULE_SCRIPT_PATH} set ${safeLat} ${safeLng} 0.0 ${safeAcc} false`;
      await execCmd(cmd);
      showToast(`Coordinates updated: ${safeLat}, ${safeLng}`);
      setTimeout(() => { state.userEditingCoords = false; }, 1500);
    }, 250);
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
    } else {
      // Button: Inactive (Start)
      el.btnMasterToggle.className = 'btn-master btn-start';
      el.textMasterToggle.textContent = 'START SPOOFING';
      el.iconMasterState.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';

      // Badges
      el.badgeStatus.className = 'badge badge-status';
      el.badgeStatusText.textContent = 'IDLE';
    }
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
        const safeLat = sanitizeNumber(state.lat, DEFAULT_LAT, -90, 90).toFixed(7);
        const safeLng = sanitizeNumber(state.lng, DEFAULT_LNG, -180, 180).toFixed(7);
        const safeAcc = sanitizeNumber(state.accuracy, 5.0, 1, 100).toFixed(1);
        await execCmd(`sh ${MODULE_SCRIPT_PATH} set ${safeLat} ${safeLng} 0.0 ${safeAcc} false`);
        
        // Launch daemon
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

    // Accuracy
    el.inputAccuracy.addEventListener('change', () => {
      state.accuracy = sanitizeNumber(el.inputAccuracy.value, 5.0, 1, 100);
      el.inputAccuracy.value = state.accuracy;
      if (state.isActive) debounceSyncToDaemon();
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

    // Target Apps Accordion Toggle
    if (el.appsToggle && el.appsBody) {
      el.appsToggle.addEventListener('click', () => {
        el.appsToggle.classList.toggle('collapsed');
        el.appsBody.classList.toggle('hidden');
      });
    }

    // Target Apps Form Add
    if (el.formAddApp) {
      el.formAddApp.addEventListener('submit', async (e) => {
        e.preventDefault();
        const pkg = (el.inputAppPkg.value || '').trim();
        if (!pkg) return;
        showToast(`Adding ${pkg}...`);
        await execCmd(`sh ${MODULE_SCRIPT_PATH} add-app ${pkg}`);
        el.inputAppPkg.value = '';
        await fetchDaemonStatus();
        showToast(`Added ${pkg}`);
      });
    }

    // Target Apps Quick Add Preset Buttons
    document.querySelectorAll('.btn-quick-app').forEach(btn => {
      btn.addEventListener('click', async () => {
        const pkg = btn.dataset.pkg;
        if (!pkg) return;
        showToast(`Adding ${pkg}...`);
        await execCmd(`sh ${MODULE_SCRIPT_PATH} add-app ${pkg}`);
        await fetchDaemonStatus();
        showToast(`Added ${pkg}`);
      });
    });

    // Target Apps Remove Button Click
    if (el.targetAppsContainer) {
      el.targetAppsContainer.addEventListener('click', async (e) => {
        const removeBtn = e.target.closest('.app-tag-remove');
        if (!removeBtn) return;
        const pkg = removeBtn.dataset.pkg;
        if (!pkg) return;
        showToast(`Removing ${pkg}...`);
        await execCmd(`sh ${MODULE_SCRIPT_PATH} remove-app ${pkg}`);
        await fetchDaemonStatus();
        showToast(`Removed ${pkg}`);
      });
    }

    // Force-stop & Clear Target App Caches Now Button
    if (el.btnEvictNow) {
      el.btnEvictNow.addEventListener('click', async () => {
        showToast("Force-stopping target apps & clearing caches...");
        await execCmd(`sh ${MODULE_SCRIPT_PATH} evict-apps`);
        showToast("Target app caches cleared!");
      });
    }
  }

  function renderTargetApps(apps) {
    state.targetApps = Array.isArray(apps) ? apps : [];
    if (el.badgeAppsCount) {
      const count = state.targetApps.length;
      el.badgeAppsCount.textContent = `${count} ${count === 1 ? 'App' : 'Apps'}`;
    }
    if (!el.targetAppsContainer) return;

    if (state.targetApps.length === 0) {
      el.targetAppsContainer.innerHTML = '<span style="font-size: 11px; color: var(--text-muted); font-style: italic; padding: 4px 0;">No target apps configured yet. Add apps above to clear their caches on location changes.</span>';
      return;
    }

    el.targetAppsContainer.innerHTML = state.targetApps.map(pkg => `
      <div class="app-tag" data-pkg="${pkg}">
        <span class="app-tag-name" title="${pkg}">${pkg}</span>
        <span class="app-tag-remove" data-pkg="${pkg}" title="Remove app">✕</span>
      </div>
    `).join('');
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
          if (isInitialLoad || !state.userEditingCoords) {
            state.lat = data.config.latitude;
            state.lng = data.config.longitude;
            state.accuracy = data.config.accuracy ?? state.accuracy;

            // Update UI controls
            el.inputAccuracy.value = state.accuracy;

            updateCoordinates(state.lat, state.lng, false);
            if (isInitialLoad && map) {
              map.setView([state.lat, state.lng], 15);
              isInitialLoad = false;
            }
          }
        }

        // Sync target apps list from config
        if (data.config && Array.isArray(data.config.target_apps)) {
          renderTargetApps(data.config.target_apps);
        }

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

    // Initial status check
    await fetchDaemonStatus();

    // Periodic telemetry refresh every 4 seconds
    setInterval(fetchDaemonStatus, 4000);
  }

  // Launch when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
