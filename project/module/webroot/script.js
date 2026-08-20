(function () {
  'use strict';

  /* ============================================================
   * MountZero VFS - Next-Gen WebUI Controller
   * Dark Glassmorphism + Neon Green & Blue Edition
   * ============================================================ */

  const MZCTL = '/data/adb/ksu/bin/mzctl';
  const KSU_SUSFS = '/data/adb/ksu/bin/ksu_susfs';

  /* ============================================================
   * Command Runner
   * ============================================================ */

  async function runCmd(cmd, timeoutMs) {
    var timeout = timeoutMs || 10000;
    try {
      if (typeof exec === 'function') {
        var result = await Promise.race([
          exec(cmd, {}),
          new Promise(function (resolve) { setTimeout(function () { resolve({ stdout: '', stderr: 'TIMEOUT' }); }, timeout); })
        ]);
        return (result.stdout || '') + (result.stderr || '');
      } else if (typeof ksu !== 'undefined' && typeof ksu.exec === 'function') {
        return new Promise((resolve) => {
          var resolved = false;
          var cbName = 'mzcb_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
          window[cbName] = (errno, stdout, stderr) => {
            if (resolved) return;
            resolved = true;
            resolve((stdout || '') + (stderr || ''));
            delete window[cbName];
          };
          ksu.exec(cmd, '{}', cbName);
          setTimeout(function () {
            if (!resolved) {
              resolved = true;
              resolve('TIMEOUT');
              delete window[cbName];
            }
          }, timeout);
        });
      }
    } catch (e) {
      return 'Error: ' + e.message;
    }
    return 'KernelSU bridge not available';
  }

  var _mzctlPath = null;
  async function runMZ(args) {
    if (!_mzctlPath) {
      var probe = await runCmd('for p in /data/adb/ksu/bin/mzctl /data/adb/modules/mountzero_vfs/bin/mzctl /data/adb/modules/mountzero_vfs/system/bin/mzctl; do test -x "$p" && echo "$p" && break; done', 8000);
      _mzctlPath = probe.trim().split('\n').pop() || 'mzctl';
    }
    return await runCmd(_mzctlPath + ' ' + args + ' 2>&1', 15000);
  }

  /* ============================================================
   * Tab Navigation
   * ============================================================ */

  document.querySelectorAll('.tab').forEach(function (tab) {
    tab.addEventListener('click', function () {
      document.querySelectorAll('.tab').forEach(function (t) { t.classList.remove('active'); });
      document.querySelectorAll('.tab-content').forEach(function (c) { c.classList.remove('active'); });
      tab.classList.add('active');
      var tabId = 'tab-' + tab.dataset.tab;
      document.getElementById(tabId).classList.add('active');

      switch (tab.dataset.tab) {
        case 'status':    loadStatus();    break;
        case 'modules':   loadModules();   break;
        case 'rules':     loadRules();     break;
        case 'config':    loadConfig();    break;
        case 'guard':     loadGuard();     break;
        case 'exclusions': loadExclusions(); break;
        case 'hiding':    loadHidingConfig(); break;
        case 'tools':     loadBBRStatus(); break;
      }
    });
  });

  /* ============================================================
   * Animated Counter Helper
   * ============================================================ */

  function animateCount(el, target) {
    var n = parseInt(target) || 0;
    if (isNaN(n) || n < 0) { el.textContent = String(target); return; }
    var start = 0;
    var step = Math.max(1, Math.ceil(n / 30));
    var timer = setInterval(function () {
      start = Math.min(start + step, n);
      el.textContent = String(start);
      if (start >= n) clearInterval(timer);
    }, 16);
  }

  function setText(id, value) {
    var el = document.getElementById(id);
    if (el) el.textContent = (value !== undefined && value !== null && value !== '') ? value : '--';
  }

  function setNeonColor(id, value, availText) {
    var el = document.getElementById(id);
    if (!el) return;
    el.textContent = value;
    if (value === availText) {
      el.style.color = 'var(--neon-green)';
      el.style.textShadow = '0 0 10px rgba(0,255,136,0.4)';
    } else {
      el.style.color = 'var(--danger)';
      el.style.textShadow = '0 0 10px rgba(255,69,96,0.3)';
    }
  }

  /* ============================================================
   * Status Tab
   * ============================================================ */

  async function loadStatus() {
    try {
      var status = await runMZ('status');
      var isEnabled = status.toUpperCase().indexOf('ENABLED') !== -1;

      var badge = document.getElementById('status-badge');
      badge.textContent = isEnabled ? 'Active' : 'Inactive';
      badge.className = 'badge ' + (isEnabled ? 'active' : 'inactive');

      var pill = document.getElementById('vfs-status-pill');
      if (pill) {
        pill.textContent = isEnabled ? 'ENABLED' : 'DISABLED';
        pill.className = 'card-badge ' + (isEnabled ? 'active' : 'inactive');
      }

      var engineEl = document.getElementById('engine-status');
      if (engineEl) {
        engineEl.textContent = isEnabled ? 'ENABLED' : 'DISABLED';
        engineEl.style.color = isEnabled ? 'var(--neon-green)' : 'var(--danger)';
        engineEl.style.textShadow = isEnabled
          ? '0 0 10px rgba(0,255,136,0.4)'
          : '0 0 10px rgba(255,69,96,0.3)';
      }

      // Count rules from list
      var rulesOutput = await runMZ('list');
      var ruleLines = rulesOutput.split('\n').filter(function (l) { return l.indexOf('REDIRECT:') === 0 && l.indexOf('REDIRECT: none') === -1 && l.indexOf(' -> ') !== -1; });
      var uniqueRules = new Set(ruleLines);
      var ruleCount = uniqueRules.size;

      // Count SUSFS paths and maps from config (default + custom)
      var config = await runCmd('cat /data/adb/mountzero/config.toml 2>/dev/null');
      var pathCount = 0;
      var mapCount = 0;
      if (config) {
        var pathHide = config.match(/pathHide\s*=\s*true/i);
        var mapsHide = config.match(/mapsHide\s*=\s*true/i);
        if (pathHide) {
          pathCount = 9;
          var customPathsMatch = config.match(/hiddenPaths\s*=\s*\[(.*?)\]/);
          if (customPathsMatch && customPathsMatch[1].trim()) {
            var customPaths = customPathsMatch[1].split(',').filter(function(p) { return p.trim().length > 2; });
            pathCount += customPaths.length;
          }
        }
        if (mapsHide) {
          mapCount = 7;
          var customMapsMatch = config.match(/hiddenMaps\s*=\s*\[(.*?)\]/);
          if (customMapsMatch && customMapsMatch[1].trim()) {
            var customMaps = customMapsMatch[1].split(',').filter(function(m) { return m.trim().length > 2; });
            mapCount += customMaps.length;
          }
        }
      }

      // Animate stat counters
      var rulesEl = document.getElementById('engine-rules');
      if (rulesEl) animateCount(rulesEl, ruleCount);
      var hiddenEl = document.getElementById('engine-hidden');
      if (hiddenEl) animateCount(hiddenEl, pathCount);
      var mapsEl = document.getElementById('engine-maps');
      if (mapsEl) animateCount(mapsEl, mapCount);
      var uidsEl = document.getElementById('engine-uids');
      if (uidsEl) {
        var allowlistCount = await runCmd('cat /data/adb/ksu/.allowlist 2>/dev/null | strings | grep -E "^[a-z]" | wc -l');
        var appsCount = await runCmd('ls -1 /data/data/ 2>/dev/null | wc -l');
        var totalBlocked = parseInt(appsCount.trim()) - parseInt(allowlistCount.trim());
        animateCount(uidsEl, totalBlocked > 0 ? totalBlocked : 0);
      }

      // SUSFS version (original exact command)
      var susfsVer = await runCmd('/data/adb/ksu/bin/ksu_susfs show version 2>/dev/null || echo --');
      setText('engine-driver', susfsVer.trim() || '--');

      // System info
      var kernel  = (await runCmd('uname -r 2>/dev/null')).trim();
      var android = (await runCmd('getprop ro.build.version.release 2>/dev/null')).trim();
      var device  = (await runCmd('getprop ro.product.model 2>/dev/null')).trim();
      var uptimeRaw = (await runCmd('cat /proc/uptime 2>/dev/null')).trim();
      var uptimeSec = parseFloat(uptimeRaw.split(' ')[0]) || 0;
      var uptimeHrs = Math.floor(uptimeSec / 3600);
      var uptimeMin = Math.floor((uptimeSec % 3600) / 60);

      setText('info-kernel', kernel || 'Unknown');
      setText('info-android', android || 'Unknown');
      setText('info-device', device || 'Unknown');
      setText('info-uptime', uptimeHrs + 'h ' + uptimeMin + 'm');

      var selinux = (await runCmd('getenforce 2>/dev/null')).trim();
      var selinuxEl = document.getElementById('info-selinux');
      if (selinuxEl) {
        selinuxEl.textContent = selinux || 'Unknown';
        selinuxEl.style.color = selinux === 'Enforcing' ? 'var(--danger)' : 'var(--neon-green)';
      }

      // Capabilities
      var detect = await runMZ('detect');
      var capVfs     = detect.indexOf('VFS driver:     AVAILABLE') !== -1 ? 'Available' : 'Not Available';
      var capOverlay = detect.indexOf('OverlayFS:      AVAILABLE') !== -1 ? 'Available' : 'Not Available';
      var capErofs   = detect.indexOf('EROFS:          AVAILABLE') !== -1 ? 'Available' : 'Not Available';

      // SUSFS — use binary, not sysfs
      var susfsBinCheck = await runCmd('for b in /data/adb/ksu/bin/ksu_susfs /data/adb/modules/mountzero_vfs/bin/susfs /data/adb/ksu/bin/susfs; do test -x "$b" && echo "$b" && break; done', 8000);
      var susfsBin = susfsBinCheck.trim();
      var capSusfs = 'Not Available';
      if (susfsBin) {
        var ver = await runCmd(susfsBin + ' show version 2>/dev/null', 8000);
        if (ver && ver.trim() && ver.trim() !== '--') {
          capSusfs = 'Available';
          setText('engine-driver', ver.trim());
        }
      }

      setNeonColor('cap-vfs',     capVfs,     'Available');
      setNeonColor('cap-susfs',   capSusfs,   'Available');
      setNeonColor('cap-overlay', capOverlay, 'Available');
      setNeonColor('cap-erofs',   capErofs,   'Available');

    } catch (e) {
      console.error('loadStatus error: ' + e);
      setText('engine-status', 'ERROR');
    }
  }

  document.getElementById('btn-refresh').addEventListener('click', loadStatus);

  document.getElementById('btn-enable-vfs').addEventListener('click', async function () {
    var result = await runMZ('enable');
    showToast(result.trim());
    loadStatus();
  });

  document.getElementById('btn-disable-vfs').addEventListener('click', async function () {
    var result = await runMZ('disable');
    showToast(result.trim());
    loadStatus();
  });

  /* ============================================================
   * Modules Tab — exact original logic
   * ============================================================ */

  async function loadModules() {
    var output = await runCmd('ls -1 /data/adb/modules/ 2>/dev/null');
    var list = document.getElementById('module-list');
    list.innerHTML = '';

    if (!output || output.includes('Permission denied') || output.includes('inaccessible') || output.trim() === '') {
      list.innerHTML = '<div class="list-empty">No modules found or no access</div>';
      return;
    }

    var modules = output.trim().split('\n').filter(function (m) { return m; });
    for (var i = 0; i < modules.length; i++) {
      var mod = modules[i];
      var item = document.createElement('div');
      item.className = 'list-item';

      var disableCheck = await runCmd('test -f /data/adb/modules/' + mod + '/disable && echo disabled || echo active');
      var isActive = !disableCheck.includes('disabled');

      var nameProp = (await runCmd('grep \'^name=\' /data/adb/modules/' + mod + '/module.prop 2>/dev/null | cut -d= -f2')).trim();
      var modName = nameProp || mod;

      item.innerHTML =
        '<div class="list-item-body">' +
          '<div class="list-item-title">' + escHtml(modName) + '</div>' +
          '<div class="list-item-sub">/data/adb/modules/' + escHtml(mod) + '</div>' +
        '</div>' +
        '<div class="list-item-actions">' +
          '<span class="status-pill ' + (isActive ? 'active' : 'disabled') + '">' + (isActive ? 'Active' : 'Disabled') + '</span>' +
        '</div>';
      list.appendChild(item);
    }
  }

  document.getElementById('module-search').addEventListener('input', function (e) {
    var query = e.target.value.toLowerCase();
    document.querySelectorAll('#module-list .list-item').forEach(function (item) {
      var text = item.querySelector('.list-item-title').textContent.toLowerCase();
      item.style.display = text.includes(query) ? '' : 'none';
    });
  });

  /* ============================================================
   * VFS Rules Tab — exact original logic
   * ============================================================ */

  async function loadRules() {
    var output = await runMZ('list');
    var list = document.getElementById('rule-list');
    list.innerHTML = '';

    var lines = output.split('\n').filter(function (l) { return l.indexOf('REDIRECT:') === 0 && l.indexOf('REDIRECT: none') === -1; });
    if (lines.length === 0) {
      list.innerHTML = '<div class="list-empty">No active rules</div>';
      return;
    }

    // Deduplicate
    var seen = new Set();
    var uniqueLines = lines.filter(function (line) {
      if (seen.has(line)) return false;
      seen.add(line);
      return true;
    });

    uniqueLines.forEach(function (line) {
      var match = line.match(/REDIRECT:\s+(.+?)\s+->\s+(.+)/);
      if (!match) return;

      var item = document.createElement('div');
      item.className = 'list-item';
      item.innerHTML =
        '<div class="list-item-body">' +
          '<div class="list-item-title" style="color:var(--neon-cyan)">' + escHtml(match[1]) + '</div>' +
          '<div class="list-item-sub">&rarr; ' + escHtml(match[2]) + '</div>' +
        '</div>' +
        '<div class="list-item-actions">' +
          '<button class="btn-icon" data-virt="' + escAttr(match[1]) + '" title="Delete rule">' +
            '<svg viewBox="0 0 20 20" fill="none"><path d="M4 7h12M6 7V5a1 1 0 011-1h6a1 1 0 011 1v2m2 0l-1 9a1 1 0 01-1 1H7a1 1 0 01-1-1L5 7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>' +
          '</button>' +
        '</div>';
      list.appendChild(item);
    });

    // Delete handlers — use 'del' exactly as original
    list.querySelectorAll('.btn-icon').forEach(function (btn) {
      btn.addEventListener('click', async function () {
        var virt = btn.dataset.virt;
        btn.disabled = true;
        try {
          var result = await runMZ('del "' + virt.replace(/"/g, '') + '"');
          showToast(result.trim() || 'Rule deleted');
        } catch (e) {
          showToast('Error deleting rule');
        }
        await loadRules();
      });
    });
  }

  document.getElementById('btn-add-rule').addEventListener('click', async function () {
    var btn = this;
    var virt = document.getElementById('rule-virt').value.trim();
    var real = document.getElementById('rule-real').value.trim();
    if (!virt || !real) {
      showToast('Both paths are required');
      return;
    }
    btn.disabled = true;
    try {
      var result = await runMZ('add "' + virt.replace(/"/g, '') + '" "' + real.replace(/"/g, '') + '"');
      showToast(result.trim() || 'Rule added');
      document.getElementById('rule-virt').value = '';
      document.getElementById('rule-real').value = '';
      await loadRules();
    } catch (e) {
      showToast('Error adding rule');
    }
    btn.disabled = false;
  });

  document.getElementById('btn-clear-rules').addEventListener('click', async function () {
    if (!confirm('Clear all VFS rules?')) return;
    var result = await runMZ('clear');
    showToast(result.trim());
    loadRules();
  });

  /* ============================================================
   * Config Tab — exact original logic
   * ============================================================ */

  async function loadConfig() {
    var config = await runCmd('cat /data/adb/mountzero/config.toml 2>/dev/null');
    if (config && !config.includes('No such file')) {
      var partMatch = config.match(/partitions\s*=\s*\[(.+?)\]/);
      if (partMatch) {
        document.getElementById('cfg-partitions').value = partMatch[1].replace(/"/g, '').replace(/\s/g, '');
      }
    }
  }

  /* Uname spoofing status — always shows real kernel info unless spoofed */
  async function loadUnameStatus() {
    try {
      /* Always get real kernel info first — use /proc/version for reliability */
      var realRelease = '';
      var realVersion = '';
      
      /* Try /proc/version first — more reliable than uname command */
      var procVer = (await runCmd('cat /proc/version')).trim();
      if (procVer) {
        /* Parse: "Linux version 4.14.356-Dev-爪卂丂ㄒ乇尺爪工刀ᗪ (user@host) (gcc ...) #1 SMP PREEMPT ..." */
        var releaseMatch = procVer.match(/Linux version\s+([^\s]+)/);
        if (releaseMatch) realRelease = releaseMatch[1];
        /* Get version string after # */
        var verMatch = procVer.match(/\)\s*(#.+)/);
        if (verMatch) realVersion = verMatch[1].trim();
      }
      
      /* Fallback to uname if proc/version parsing failed */
      if (!realRelease || realRelease.length <= 5) {
        for (var attempt = 0; attempt < 3; attempt++) {
          realRelease = (await runCmd('uname -r')).trim();
          realVersion = (await runCmd('uname -v')).trim();
          if (realRelease && realRelease.length > 5) break;
          await new Promise(function(resolve) { setTimeout(resolve, 1000); });
        }
      }
      
      /* Check if we have saved spoofed values */
      var spoofedRelease = (await runCmd('cat /data/adb/mountzero/uname_release 2>/dev/null')).trim();
      var spoofedVersion = (await runCmd('cat /data/adb/mountzero/uname_version 2>/dev/null')).trim();
      
      var statusEl = document.getElementById('uname-status-text');
      var relEl = document.getElementById('uname-release-display');
      var verEl = document.getElementById('uname-version-display');

      /* Show spoofed values only if they exist and differ from real */
      if (spoofedRelease && spoofedRelease !== realRelease && spoofedRelease.length > 3) {
        if (statusEl) { statusEl.textContent = 'Spoofed'; statusEl.style.color = '#00ff88'; }
        if (relEl) relEl.textContent = spoofedRelease;
        if (verEl) verEl.textContent = spoofedVersion;
      } else {
        /* Show real kernel info */
        if (statusEl) { statusEl.textContent = 'Real Kernel'; statusEl.style.color = '#00f5ff'; }
        if (relEl) relEl.textContent = realRelease || 'Loading...';
        if (verEl) verEl.textContent = realVersion || 'Loading...';
      }
    } catch (e) {
      console.error('loadUnameStatus error:', e);
    }
  }

  /* Load uname status with delay on initial page load to ensure shell bridge is ready */
  setTimeout(loadUnameStatus, 1000);
  setTimeout(loadUnameToggleState, 1500);
  setTimeout(loadBBRStatus, 2000);
  setTimeout(loadMemGuardStatus, 2500);

  /* Hardcoded default spoofed uname values (stock-looking kernel version) */
  var DEFAULT_SPOOFED_RELEASE = '4.14.194-g5a9c3d7e6f2b';
  var DEFAULT_SPOOFED_VERSION = '#1 SMP PREEMPT Thu Jan 15 03:42:17 UTC 2025';

  /* Pre-fill input fields with hardcoded defaults */
  document.getElementById('cfg-uname-release').value = DEFAULT_SPOOFED_RELEASE;
  document.getElementById('cfg-uname-version').value = DEFAULT_SPOOFED_VERSION;

  document.getElementById('btn-apply-uname').addEventListener('click', async function () {
    var release = document.getElementById('cfg-uname-release').value.trim();
    var version = document.getElementById('cfg-uname-version').value.trim();
    if (!release) release = DEFAULT_SPOOFED_RELEASE;
    if (!version) version = DEFAULT_SPOOFED_VERSION;
    
    /* Try all possible susfs binary paths */
    var cmd = 'for b in /data/adb/ksu/bin/susfs /data/adb/modules/mountzero_vfs/bin/susfs /data/adb/ap/bin/susfs; do ' +
              'if [ -x "$b" ]; then ' +
              '  "$b" set_uname "' + release + '" "' + version + '" 2>&1; ' +
              '  break; ' +
              'fi; ' +
              'done';
    var result = await runCmd(cmd);
    /* Save spoofed values for status display */
    await runCmd('mkdir -p /data/adb/mountzero && echo "' + release + '" > /data/adb/mountzero/uname_release && echo "' + version + '" > /data/adb/mountzero/uname_version');
    showToast(result.trim() || 'Uname spoofed');
    loadUnameStatus();
  });

  document.getElementById('btn-reset-uname').addEventListener('click', async function () {
    if (!confirm('Restore actual kernel version?')) return;
    /* Use SUSFS default to restore real kernel version */
    var cmd = 'for b in /data/adb/ksu/bin/susfs /data/adb/modules/mountzero_vfs/bin/susfs /data/adb/ap/bin/susfs; do ' +
              'if [ -x "$b" ]; then ' +
              '  "$b" set_uname default default 2>&1; ' +
              '  break; ' +
              'fi; ' +
              'done';
    var result = await runCmd(cmd);
    /* Clear saved spoofed values */
    await runCmd('rm -f /data/adb/mountzero/uname_release /data/adb/mountzero/uname_version /data/adb/mountzero/uname_spoof_enabled');
    showToast('Restored actual kernel version');
    loadUnameStatus();
    loadStatus();
  });

  /* Auto-spoof toggle */
  document.getElementById('cfg-uname-autospoof').addEventListener('change', async function () {
    var enabled = this.checked ? '1' : '0';
    await runCmd('mkdir -p /data/adb/mountzero && echo ' + enabled + ' > /data/adb/mountzero/uname_spoof_enabled');
    if (this.checked) {
      showToast('Auto-spoof enabled at boot');
      /* Also apply immediately */
      var release = document.getElementById('cfg-uname-release').value.trim() || DEFAULT_SPOOFED_RELEASE;
      var version = document.getElementById('cfg-uname-version').value.trim() || DEFAULT_SPOOFED_VERSION;
      await runCmd('mkdir -p /data/adb/mountzero && echo "' + release + '" > /data/adb/mountzero/uname_release && echo "' + version + '" > /data/adb/mountzero/uname_version');
      await runCmd('for b in /data/adb/ksu/bin/susfs /data/adb/modules/mountzero_vfs/bin/susfs /data/adb/ap/bin/susfs; do test -x "$b" && "$b" set_uname "' + release + '" "' + version + '" 2>&1 && break; done');
    } else {
      showToast('Auto-spoof disabled at boot');
    }
    loadUnameStatus();
  });

  /* Load auto-spoof toggle state */
  async function loadUnameToggleState() {
    var val = (await runCmd('cat /data/adb/mountzero/uname_spoof_enabled 2>/dev/null')).trim();
    var cb = document.getElementById('cfg-uname-autospoof');
    if (cb) cb.checked = (val === '1');
  }

  document.getElementById('btn-save-config').addEventListener('click', async function () {
    var partitions   = document.getElementById('cfg-partitions').value.trim();
    var selinuxSpoof = document.getElementById('cfg-selinux-spoof').checked;
    var hideMounts   = document.getElementById('cfg-hide-mounts').checked;
    var adbRoot      = document.getElementById('cfg-adb-root').checked;
    var mountEngine  = document.getElementById('cfg-mount-engine').value;

    var parts = partitions.split(',').map(function (p) { return '"' + p.trim() + '"'; }).filter(function (p) { return p !== '""'; }).join(', ');
    var config = '[mount]\npartitions = [' + parts + ']\nselinux_spoof = ' + selinuxSpoof + '\nhide_mounts = ' + hideMounts + '\n\n[adb]\nroot = ' + adbRoot + '\n';

    await runCmd("mkdir -p /data/adb/mountzero && echo '" + config + "' > /data/adb/mountzero/config.toml");
    showToast('Config saved');
  });

  document.getElementById('btn-reset-config').addEventListener('click', function () {
    document.getElementById('cfg-partitions').value = 'product, system_ext, vendor';
    document.getElementById('cfg-selinux-spoof').checked = true;
    document.getElementById('cfg-hide-mounts').checked = true;
    document.getElementById('cfg-adb-root').checked = false;
    showToast('Config reset to defaults');
  });

  document.getElementById('btn-apply-adb').addEventListener('click', async function () {
    var enabled = document.getElementById('cfg-adb-root').checked;
    if (enabled) {
      await runCmd('setprop service.adb.root 1 && /system/bin/stop adbd && /system/bin/start adbd');
      showToast('ADB root enabled — reconnect USB cable');
    } else {
      await runCmd('setprop service.adb.root 0 && /system/bin/stop adbd && /system/bin/start adbd');
      showToast('ADB root disabled');
    }
    /* Also save to config for persistence */
    await runCmd('mkdir -p /data/adb/mountzero && echo ' + (enabled ? 'true' : 'false') + ' > /data/adb/mountzero/adb_root');
  });

  /* ============================================================
   * Guard Tab — exact original logic
   * ============================================================ */

  async function loadGuard() {
    var output = await runMZ('guard check');
    var lines = output.split('\n');
    var count = 0;
    var threshold = 3;

    lines.forEach(function (line) {
      var m = line.match(/Boot count:\s+(\d+)/);
      if (m) {
        count = parseInt(m[1]);
        var statusText = count >= threshold ? 'TRIPPED' : 'OK';
        var countEl = document.getElementById('guard-count');
        if (countEl) animateCount(countEl, count);
        var statusEl = document.getElementById('guard-status');
        if (statusEl) {
          statusEl.textContent = statusText;
          statusEl.style.color = statusText === 'TRIPPED' ? 'var(--danger)' : 'var(--neon-green)';
          statusEl.style.textShadow = statusText === 'TRIPPED'
            ? '0 0 10px rgba(255,69,96,0.4)'
            : '0 0 10px rgba(0,255,136,0.4)';
        }
      }
      var m2 = line.match(/Threshold:\s+(\d+)/);
      if (m2) {
        threshold = parseInt(m2[1]);
        setText('guard-threshold', m2[1]);
      }
    });

    // Update the ring arc
    var arc = document.getElementById('guard-ring-arc');
    if (arc) {
      var ratio = threshold > 0 ? Math.min(count / threshold, 1) : 0;
      var circumference = 314;
      arc.style.strokeDashoffset = String(circumference - ratio * circumference);
    }
  }

  document.getElementById('btn-check-guard').addEventListener('click', loadGuard);

  document.getElementById('btn-recover-guard').addEventListener('click', async function () {
    var result = await runMZ('guard recover');
    showToast(result.trim());
    loadGuard();
  });

  /* ============================================================
   * Tools Tab — exact original logic
   * ============================================================ */

  document.getElementById('btn-detect').addEventListener('click', async function () {
    var output = await runMZ('detect');
    var el = document.getElementById('detect-output');
    if (el) el.textContent = output;
  });

  document.getElementById('btn-dump').addEventListener('click', async function () {
    showToast('Creating diagnostic dump...');
    var output = await runMZ('dump');
    var el = document.getElementById('detect-output');
    if (el) el.textContent = output;
  });

  /* BBR Congestion Control — check actual kernel state */
  async function loadBBRStatus() {
    try {
      var algo = (await runCmd('cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null')).trim();
      var available = (await runCmd('cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null')).trim();
      
      var algoEl = document.getElementById('bbr-current-algo');
      if (algoEl) algoEl.textContent = algo || 'Unknown';
      
      var statusEl = document.getElementById('bbr-status-text');
      if (statusEl) {
        if (algo.indexOf('bbr') !== -1) {
          statusEl.textContent = 'BBR Active';
          statusEl.style.color = '#00ff88';
        } else if (available.indexOf('bbr') !== -1) {
          statusEl.textContent = 'BBR available (using ' + algo + ')';
          statusEl.style.color = '#d29922';
        } else {
          statusEl.textContent = 'BBR not compiled in kernel';
          statusEl.style.color = '#8b949e';
        }
      }

      /* Update toggle switch state based on actual kernel value */
      var bbrEnabled = algo.indexOf('bbr') !== -1;
      var toggleCb = document.getElementById('bbr-toggle');
      if (toggleCb) toggleCb.checked = bbrEnabled;
      
      window._bbrAvailable = available;
    } catch (e) { console.error('loadBBRStatus error:', e); }
  }

  /* MemGuard Control */
  async function loadMemGuardStatus() {
    try {
      var disabled = await runCmd('test -f /data/adb/modules/memguard/disable && echo disabled || echo enabled');
      var isEnabled = !disabled.includes('disabled');
      
      var pill = document.getElementById('memguard-status-pill');
      var statusEl = document.getElementById('memguard-status-text');
      var toggleCb = document.getElementById('memguard-toggle');
      
      if (pill) {
        pill.textContent = isEnabled ? 'ENABLED' : 'DISABLED';
        pill.className = 'card-badge ' + (isEnabled ? 'active' : 'inactive');
      }
      
      if (statusEl) {
        statusEl.textContent = isEnabled ? 'Active' : 'Disabled';
        statusEl.style.color = isEnabled ? '#00ff88' : '#8b949e';
      }
      
      if (toggleCb) toggleCb.checked = isEnabled;
    } catch (e) {
      console.error('loadMemGuardStatus error:', e);
    }
  }

  document.getElementById('memguard-toggle').addEventListener('change', async function () {
    var enabled = this.checked;
    if (enabled) {
      showToast('Removing MemGuard disable flag...');
      await runCmd('rm -f /data/adb/modules/memguard/disable 2>/dev/null');
      showToast('MemGuard enabled — reboot to apply');
    } else {
      showToast('Creating MemGuard disable flag...');
      await runCmd('mkdir -p /data/adb/modules/memguard && touch /data/adb/modules/memguard/disable 2>/dev/null');
      showToast('MemGuard disabled — reboot to apply');
    }
    loadMemGuardStatus();
  });

  /* BBR toggle switch — enables/disables BBR and saves state */
  document.getElementById('bbr-toggle').addEventListener('change', async function () {
    var enabled = this.checked;
    if (enabled) {
      showToast('Enabling BBR...');
      await runCmd('su -c "sysctl -w net.core.default_qdisc=fq" 2>/dev/null');
      await runCmd('su -c "echo bbr > /proc/sys/net/ipv4/tcp_congestion_control" 2>/dev/null');
      var result = await runCmd('cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null');
      if (result.indexOf('bbr') !== -1) {
        await runCmd('mkdir -p /data/adb/mountzero && echo 1 > /data/adb/mountzero/bbr_enabled');
        showToast('BBR enabled — persists across reboots');
      } else {
        showToast('BBR enable failed. Available: ' + (window._bbrAvailable || ''));
        this.checked = false;
      }
    } else {
      showToast('Disabling BBR...');
      await runCmd('su -c "echo cubic > /proc/sys/net/ipv4/tcp_congestion_control" 2>/dev/null');
      await runCmd('mkdir -p /data/adb/mountzero && echo 0 > /data/adb/mountzero/bbr_enabled');
      showToast('BBR disabled');
    }
    loadBBRStatus();
  });

  document.getElementById('btn-install-module').addEventListener('click', async function () {
    var modId   = document.getElementById('tool-mod-id').value.trim();
    var modPath = document.getElementById('tool-mod-path').value.trim();
    var isCustom = document.getElementById('tool-mod-custom').checked;

    if (!modId || !modPath) {
      showToast('Module ID and path are required');
      return;
    }

    var args = isCustom
      ? 'module install "' + modId + '" "' + modPath + '" custom'
      : 'module install "' + modId + '" "' + modPath + '"';
    var result = await runMZ(args);
    showToast(result.trim());
  });

  document.getElementById('btn-scan-modules').addEventListener('click', async function () {
    showToast('Scanning all modules...');
    var output = await runMZ('module scan');
    var el = document.getElementById('detect-output');
    if (el) el.textContent = output;
    loadRules();
    loadStatus();
  });

  /* ============================================================
   * Hiding Tab — BRENE config, custom rules, logs
   * ============================================================ */

  async function loadHidingConfig() {
    try {
      var config = await runCmd('cat /data/adb/mountzero/config.toml 2>/dev/null');

      var getVal = function(section, key, def) {
        var inSec = false;
        var lines = config.split('\n');
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line === '[' + section + ']') { inSec = true; continue; }
          if (line.match(/^\[/)) { inSec = false; continue; }
          if (inSec) {
            var parts = line.split('=');
            if (parts[0] && parts[0].trim() === key) {
              var v = parts.slice(1).join('=').trim().replace(/^["']|["']$/g, '');
              return v;
            }
          }
        }
        return def;
      };

      document.getElementById('cfg-hide-injections').checked = getVal('ghost', 'autoHideInjections', 'true') === 'true';
      document.getElementById('cfg-hide-tmp').checked = getVal('ghost', 'hideDataLocalTmp', 'true') === 'true';
      document.getElementById('cfg-hide-zygisk-modules').checked = getVal('ghost', 'hideZygiskModules', 'true') === 'true';
      document.getElementById('cfg-hide-sus-mounts').checked = getVal('ghost', 'hideSusMounts', 'true') === 'true';
      document.getElementById('cfg-avc-spoof').checked = getVal('susfs', 'avcLogSpoofing', 'false') === 'true';
      document.getElementById('cfg-cmdline-spoof').checked = getVal('ghost', 'spoofCmdline', 'true') === 'true';
      document.getElementById('cfg-prop-spoof').checked = getVal('ghost', 'propSpoofing', 'true') === 'true';
      document.getElementById('cfg-hide-sdcard').checked = getVal('ghost', 'nonStandardSdcardPathsHiding', 'false') === 'true';
      document.getElementById('cfg-hide-sdcard-android').checked = getVal('ghost', 'nonStandardSdcardAndroidPathsHiding', 'false') === 'true';
      document.getElementById('cfg-hide-lsposed').checked = getVal('ghost', 'hideLsposed', 'false') === 'true';
      document.getElementById('cfg-hide-loops').checked = getVal('ghost', 'hideLoops', 'true') === 'true';
      document.getElementById('cfg-kernel-umount').checked = getVal('ghost', 'kernelUmount', 'true') === 'true';
      document.getElementById('cfg-uname-spoof').checked = getVal('ghost', 'unameSpoofing', 'true') === 'true';
      document.getElementById('cfg-selinux').checked = getVal('ghost', 'selinux', 'true') === 'true';
      document.getElementById('cfg-hide-modules-img').checked = getVal('ghost', 'hideModulesImg', 'false') === 'true';
      document.getElementById('cfg-hide-android-data').checked = getVal('ghost', 'hideAndroidData', 'false') === 'true';
      document.getElementById('cfg-hide-module-injections').checked = getVal('ghost', 'hideModuleInjections', 'false') === 'true';
      document.getElementById('cfg-zygisk-auto-scan').checked = getVal('ghost', 'zygiskAutoScan', 'false') === 'true';
      document.getElementById('cfg-hide-recovery').checked = getVal('ghost', 'hideRecovery', 'true') === 'true';
      document.getElementById('cfg-cleanup-leftovers').checked = getVal('ghost', 'cleanupLeftovers', 'false') === 'true';
      document.getElementById('cfg-inotify-watcher').checked = getVal('ghost', 'inotifyWatcher', 'false') === 'true';
      document.getElementById('cfg-selinux-enforce').checked = getVal('ghost', 'selinuxEnforce', 'false') === 'true';

      var vbh = getVal('ghost', 'verifiedBootHash', '');
      if (vbh && vbh !== '""') document.getElementById('cfg-vbh').value = vbh;

      var customPaths = await runCmd('cat /data/adb/mountzero/custom_sus_path.txt 2>/dev/null');
      if (customPaths && !customPaths.includes('No such')) {
        document.getElementById('cfg-custom-paths').value = customPaths.trim();
      }

      var customMaps = await runCmd('cat /data/adb/mountzero/custom_sus_map.txt 2>/dev/null');
      if (customMaps && !customMaps.includes('No such')) {
        document.getElementById('cfg-custom-maps').value = customMaps.trim();
      }

      var pill = document.getElementById('hiding-status-pill');
      if (pill) {
        pill.textContent = 'CONFIGURED';
        pill.className = 'card-badge active';
      }

      loadHidingLogs();
    } catch (e) {
      console.error('loadHidingConfig error: ' + e);
    }
  }

  async function loadHidingLogs() {
    var el = document.getElementById('hiding-logs-output');
    if (!el) return;
    var logs = await runCmd('cat /data/adb/mountzero/logs.txt 2>/dev/null || echo "No logs available"');
    el.textContent = logs.trim() || 'No logs available';
  }

  document.getElementById('btn-apply-hiding').addEventListener('click', async function () {
    showToast('Applying...');
    try {
      var configDir = '/data/adb/mountzero';
      var hideInjections = document.getElementById('cfg-hide-injections').checked;
      var hideTmp = document.getElementById('cfg-hide-tmp').checked;
      var hideZygiskModules = document.getElementById('cfg-hide-zygisk-modules').checked;
      var hideSusMounts = document.getElementById('cfg-hide-sus-mounts').checked;
      var avcSpoof = document.getElementById('cfg-avc-spoof').checked;
      var cmdlineSpoof = document.getElementById('cfg-cmdline-spoof').checked;
      var propSpoof = document.getElementById('cfg-prop-spoof').checked;
      var hideSdcard = document.getElementById('cfg-hide-sdcard').checked;
      var hideSdcardAndroid = document.getElementById('cfg-hide-sdcard-android').checked;
      var kernelUmount = document.getElementById('cfg-kernel-umount').checked;
      var unameSpoof = document.getElementById('cfg-uname-spoof').checked;
      var selinux = document.getElementById('cfg-selinux').checked;
      var hideModulesImg = document.getElementById('cfg-hide-modules-img').checked;
      var hideAndroidData = document.getElementById('cfg-hide-android-data').checked;
      var hideModuleInjections = document.getElementById('cfg-hide-module-injections').checked;
      var zygiskAutoScan = document.getElementById('cfg-zygisk-auto-scan').checked;
      var hideRecovery = document.getElementById('cfg-hide-recovery').checked;
      var cleanupLeftovers = document.getElementById('cfg-cleanup-leftovers').checked;
      var inotifyWatcher = document.getElementById('cfg-inotify-watcher').checked;
      var selinuxEnforce = document.getElementById('cfg-selinux-enforce').checked;
      var hideLsposed = document.getElementById('cfg-hide-lsposed').checked;
      var hideLoops = document.getElementById('cfg-hide-loops').checked;
      var vbh = document.getElementById('cfg-vbh').value.trim();

      var existingConfig = await runCmd('cat ' + configDir + '/config.toml 2>/dev/null');
      if (!existingConfig || existingConfig.includes('No such file')) {
        await runCmd('mkdir -p ' + configDir);
        existingConfig = '';
      }

      var ghostSection = '[ghost]\n' +
        'verifiedBootHash = "' + vbh + '"\n' +
        'kernelUmount = ' + kernelUmount + '\n' +
        'autoHideInjections = ' + hideInjections + '\n' +
        'hideDataLocalTmp = ' + hideTmp + '\n' +
        'hideZygiskModules = ' + hideZygiskModules + '\n' +
        'hideSusMounts = ' + hideSusMounts + '\n' +
        'avcLogSpoofing = ' + avcSpoof.toString() + '\n' +
        'spoofCmdline = ' + cmdlineSpoof + '\n' +
        'propSpoofing = ' + propSpoof + '\n' +
        'nonStandardSdcardPathsHiding = ' + hideSdcard + '\n' +
        'nonStandardSdcardAndroidPathsHiding = ' + hideSdcardAndroid + '\n' +
        'unameSpoofing = ' + unameSpoof + '\n' +
        'selinux = ' + selinux + '\n' +
        'hideModulesImg = ' + hideModulesImg + '\n' +
        'hideAndroidData = ' + hideAndroidData + '\n' +
        'hideModuleInjections = ' + hideModuleInjections + '\n' +
        'zygiskAutoScan = ' + zygiskAutoScan + '\n' +
        'hideRecovery = ' + hideRecovery + '\n' +
        'cleanupLeftovers = ' + cleanupLeftovers + '\n' +
        'inotifyWatcher = ' + inotifyWatcher + '\n' +
        'selinuxEnforce = ' + selinuxEnforce + '\n' +
        'hideLsposed = ' + hideLsposed + '\n' +
        'hideLoops = ' + hideLoops;

      var mountSection = "[mount]\nmountEngine = \"vfs\"\npartitions = [\"product\", \"system_ext\", \"vendor\"]\nselinux_spoof = true\nhide_mounts = true";
      var susfsSection = "[susfs]\nenabled = true\npathHide = true\nmapsHide = true\nkstat = true\nsusfsLog = false\navcLogSpoofing = false";
      var adbSection = "[adb]\nroot = false";
      var fullConfig = mountSection + "\n\n" + susfsSection + "\n\n" + ghostSection + "\n\n" + adbSection + "\n";
      await runCmd("mkdir -p " + configDir + " && echo '" + fullConfig.replace(/'/g, "'\\''") + "' > " + configDir + "/config.toml");

      var hidingSh = '/data/adb/modules/mountzero_vfs/hiding.sh';
      var results = [];
      results.push(await runCmd(hidingSh + ' paths 2>&1'));
      results.push(await runCmd(hidingSh + ' spoof 2>&1'));
      results.push(await runCmd(hidingSh + ' mounts 2>&1'));
      results.push(await runCmd(hidingSh + ' lsposed 2>&1'));
      results.push(await runCmd(hidingSh + ' loops 2>&1'));
      if (hideSdcard || hideSdcardAndroid || hideAndroidData) results.push(await runCmd(hidingSh + ' sdcard 2>&1'));
      if (hideModuleInjections || zygiskAutoScan) results.push(await runCmd(hidingSh + ' injections 2>&1'));
      if (hideRecovery) results.push(await runCmd(hidingSh + ' recovery 2>&1'));
      if (cleanupLeftovers) results.push(await runCmd(hidingSh + ' cleanup 2>&1'));
      if (inotifyWatcher) results.push(await runCmd(hidingSh + ' inotify 2>&1'));
      if (selinuxEnforce) results.push(await runCmd(hidingSh + ' selinux 2>&1'));

      var successCount = results.filter(function(r) { return !r.includes('FAILED'); }).length;
      showToast('Hiding applied: ' + successCount + ' phases succeeded');
      loadHidingLogs();
    } catch (e) {
      showToast('Error: ' + e.message);
      console.error('apply-hiding error:', e);
    }
  });

  document.getElementById('btn-save-custom-paths').addEventListener('click', async function () {
    var paths = document.getElementById('cfg-custom-paths').value.trim();
    if (!paths) { showToast('No paths entered'); return; }
    var pathList = paths.split('\n').filter(function(p) { return p.trim(); });
    await runCmd("/data/adb/ksu/bin/mzctl config set susfs.hiddenPaths '" + JSON.stringify(pathList) + "' 2>/dev/null || echo 'Using fallback'");
    showToast('Custom path rules saved');
  });

  document.getElementById('btn-save-custom-maps').addEventListener('click', async function () {
    var maps = document.getElementById('cfg-custom-maps').value.trim();
    if (!maps) { showToast('No maps entered'); return; }
    var mapList = maps.split('\n').filter(function(m) { return m.trim(); });
    await runCmd("/data/adb/ksu/bin/mzctl config set susfs.hiddenMaps '" + JSON.stringify(mapList) + "' 2>/dev/null || echo 'Using fallback'");
    showToast('Custom map rules saved');
  });

  document.getElementById('btn-refresh-logs').addEventListener('click', loadHidingLogs);

  /* ============================================================
   * Exclusions Tab — UID-based app exclusion manager
   * ============================================================ */

  var MZ_DATA = '/data/adb/mountzero';
  var EXCLUSION_FILE = MZ_DATA + '/.exclusion_list';
  var APP_ICON_FALLBACK = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iIzgwODA4MCI+PHBhdGggZD0iTTEyIDJDNi40OCAyIDIgNi40OCAyIDEyczQuNDggMTAgMTAgMTAgMTAtNC40IDEwLTEwUzE3LjUyIDIgMTIgMnptMThjLTQuNDEgMC04LTMuNTktOC04czMuNTktOCA4LTggOCAzLTLuNDkgOC04eiIvPjwvc3ZnPg==";
  var allAppsCache = [];
  var appLoadingPromise = null;
  var showSystemApps = false;

  function parseUidList(text) {
    return String(text || '').split(/[\s,]+/).map(function (s) {
      return s.trim();
    }).filter(function (s) {
      return /^\d+$/.test(s);
    });
  }

  function normalizeUidList(uids) {
    var seen = {};
    return uids.filter(function (uid) {
      var s = String(uid || '').trim();
      if (!/^\d+$/.test(s)) return false;
      if (seen[s]) return false;
      seen[s] = true;
      return true;
    });
  }

  function buildWriteUidListCmd(uids) {
    var safe = normalizeUidList(uids);
    var tempFile = EXCLUSION_FILE + '.tmp';
    var write = safe.length > 0
      ? 'printf \'%s\\n\' ' + safe.join(' ')
      : ':';
    return 'mkdir -p ' + MZ_DATA + ' && { ' + write + ' > ' + tempFile + ' && mv -f ' + tempFile + ' ' + EXCLUSION_FILE + '; }';
  }

  async function ensureAppsCache() {
    if (allAppsCache.length > 0) return;
    if (appLoadingPromise) { await appLoadingPromise; return; }
    appLoadingPromise = (async function () {
      try {
        var ksuWait = 25;
        while ((typeof ksu === 'undefined' || !ksu.listPackages) && ksuWait > 0) {
          await new Promise(function (r) { setTimeout(r, 200); });
          ksuWait--;
        }
        if (typeof ksu === 'undefined' || !ksu.listPackages) return;
        var pkgsRaw = ksu.listPackages('all');
        if (!pkgsRaw || pkgsRaw === '[]' || pkgsRaw === '') return;
        var pkgs = JSON.parse(pkgsRaw);
        var chunkSize = 200;
        var tempCache = [];
        for (var i = 0; i < pkgs.length; i += chunkSize) {
          var chunkInfo = ksu.getPackagesInfo(JSON.stringify(pkgs.slice(i, i + chunkSize)));
          if (chunkInfo) tempCache.push.apply(tempCache, JSON.parse(chunkInfo));
          await new Promise(function (r) { setTimeout(r, 15); });
        }
        allAppsCache = tempCache.map(function (app) {
          return Object.assign({}, app, {
            appLabel: app.appLabel || app.packageName,
            uid: String(app.uid),
            _search: (app.appLabel || app.packageName).toLowerCase() + ' ' + app.packageName.toLowerCase()
          });
        }).sort(function (a, b) { return a.appLabel < b.appLabel ? -1 : a.appLabel > b.appLabel ? 1 : 0; });
      } catch (e) { console.error('ensureAppsCache:', e); }
      finally { appLoadingPromise = null; }
    })();
    return appLoadingPromise;
  }

  async function loadExclusions() {
    var listEl = document.getElementById('exclusion-list');
    if (!listEl) return;
    try {
      var readResult = await runCmd('cat ' + EXCLUSION_FILE + ' 2>/dev/null || echo ""');
      var blockedUids = parseUidList(readResult);
      if (blockedUids.length > 0) {
        try { await ensureAppsCache(); } catch (e) {}
      }
      var appsMap = {};
      allAppsCache.forEach(function (app) { appsMap[app.uid] = app; });

      var countPill = document.getElementById('exclusion-count-pill');
      if (countPill) countPill.textContent = blockedUids.length + ' app' + (blockedUids.length !== 1 ? 's' : '');

      if (blockedUids.length === 0) {
        listEl.innerHTML = '<div class="list-empty">No exclusions yet. Apps below will see the original filesystem.</div>';
        return;
      }

      var html = '';
      blockedUids.forEach(function (uid) {
        var app = appsMap[uid];
        var label = app ? app.appLabel : 'UID: ' + uid;
        var pkg = app ? app.packageName : 'system';
        html += '<div class="exclusion-item" data-uid="' + uid + '" data-label="' + escAttr(label) + '">' +
          '<img src="ksu://icon/' + escAttr(pkg) + '" class="exclusion-app-icon" onerror="this.src=\'' + APP_ICON_FALLBACK + '\'" />' +
          '<div class="exclusion-app-info">' +
            '<div class="exclusion-app-name">' + escHtml(label) + '</div>' +
            '<div class="exclusion-app-pkg">' + escHtml(pkg) + '</div>' +
          '</div>' +
          '<span class="exclusion-app-uid">UID:' + uid + '</span>' +
          '<button class="exclusion-remove-btn" title="Remove exclusion">' +
            '<svg viewBox="0 0 20 20" fill="none"><path d="M6 6l8 8M14 6l-8 8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>' +
          '</button>' +
        '</div>';
      });
      listEl.innerHTML = html;
    } catch (e) {
      listEl.innerHTML = '<div class="list-empty">Error loading exclusions</div>';
    }
  }

  async function addExclusion(uid, name) {
    uid = normalizeUidList([uid])[0];
    if (!uid) { showToast('Invalid UID'); return; }
    try {
      var readResult = await runCmd('cat ' + EXCLUSION_FILE + ' 2>/dev/null || echo ""');
      var currentUids = parseUidList(readResult);
      var alreadyBlocked = currentUids.indexOf(uid) !== -1;
      if (!alreadyBlocked) {
        currentUids.push(uid);
        await runCmd(buildWriteUidListCmd(currentUids));
      }
      await runMZ('block ' + uid);
      showToast(alreadyBlocked ? 'Already blocked' : 'Blocked: ' + name);
    } catch (e) {
      showToast('Error blocking app');
    }
    loadExclusions();
  }

  async function removeExclusion(uid, name) {
    uid = normalizeUidList([uid])[0];
    if (!uid) return;
    try {
      var readResult = await runCmd('cat ' + EXCLUSION_FILE + ' 2>/dev/null || echo ""');
      var remaining = parseUidList(readResult).filter(function (v) { return v !== uid; });
      await runCmd(buildWriteUidListCmd(remaining));
      await runMZ('unblock ' + uid);
      showToast('Unblocked: ' + name);
    } catch (e) {
      showToast('Error unblocking app');
    }
    loadExclusions();
  }

  function openAppSelector() {
    var modal = document.getElementById('app-selector-modal');
    var container = document.getElementById('app-list-container');
    var searchInput = document.getElementById('app-search-input');
    var sysSwitch = document.getElementById('switch-system-apps');
    if (!modal) return;
    modal.classList.add('active');
    searchInput.value = '';
    if (sysSwitch) sysSwitch.checked = showSystemApps;
    container.innerHTML = '<div class="list-empty">Loading apps...</div>';

    document.getElementById('btn-close-modal').onclick = function () {
      modal.classList.remove('active');
    };

    setTimeout(async function () {
      try {
        await Promise.race([
          ensureAppsCache(),
          new Promise(function (_, reject) { setTimeout(function () { reject(new Error('timeout')); }, 8000); })
        ]);
        if (allAppsCache.length === 0) {
          container.innerHTML = '<div class="list-empty">No apps found. KSU bridge may be unavailable.</div>';
          return;
        }
        renderAppList('');
        searchInput.oninput = function () { renderAppList(searchInput.value); };
        if (sysSwitch) sysSwitch.onchange = function () { showSystemApps = sysSwitch.checked; renderAppList(searchInput.value); };
      } catch (e) {
        container.innerHTML = '<div class="list-empty">Failed to load apps (' + (e.message || 'error') + ')</div>';
      }
    }, 250);
  }

  function renderAppList(searchTerm) {
    var term = (searchTerm || '').toLowerCase();
    var container = document.getElementById('app-list-container');
    if (!container) return;
    var filtered = allAppsCache.filter(function (app) {
      return app._search.indexOf(term) !== -1 && (showSystemApps || !app.isSystem);
    });
    if (filtered.length === 0) {
      container.innerHTML = '<div class="list-empty">No apps match</div>';
      return;
    }
    var html = filtered.map(function (app) {
      return '<div class="app-select-item" data-uid="' + app.uid + '" data-label="' + escAttr(app.appLabel) + '">' +
        '<img src="ksu://icon/' + escAttr(app.packageName) + '" class="app-select-icon" loading="lazy" onerror="this.src=\'' + APP_ICON_FALLBACK + '\'" />' +
        '<div class="app-select-info">' +
          '<div class="app-select-name">' + escHtml(app.appLabel) + '</div>' +
          '<div class="app-select-pkg">' + escHtml(app.packageName) + '</div>' +
        '</div>' +
        '<span class="app-select-uid">UID:' + app.uid + '</span>' +
        (app.isSystem ? '<span class="app-select-sys">SYS</span>' : '') +
      '</div>';
    }).join('');
    container.innerHTML = html;
  }

  /* Event delegation — single listeners on containers, like NoMount */
  document.getElementById('app-list-container').addEventListener('click', function (e) {
    var item = e.target.closest('.app-select-item');
    if (item && !item.dataset.busy) {
      item.dataset.busy = '1';
      var uid = item.dataset.uid;
      var label = item.dataset.label;
      document.getElementById('app-selector-modal').classList.remove('active');
      setTimeout(function () { addExclusion(uid, label); }, 50);
    }
  });

  document.getElementById('app-selector-modal').addEventListener('click', function (e) {
    if (e.target === e.currentTarget) {
      e.currentTarget.classList.remove('active');
    }
  });

  document.getElementById('btn-add-exclusion').addEventListener('click', openAppSelector);

  document.getElementById('btn-clear-exclusions').addEventListener('click', async function () {
    if (!confirm('Clear all UID exclusions?')) return;
    try {
      await runCmd(buildWriteUidListCmd([]));
      showToast('All exclusions cleared');
    } catch (e) {
      showToast('Error clearing exclusions');
    }
    loadExclusions();
  });

  document.getElementById('exclusion-list').addEventListener('click', function (e) {
    var btn = e.target.closest('.exclusion-remove-btn');
    if (!btn) return;
    var item = btn.closest('.exclusion-item');
    if (!item) return;
    var uid = item.dataset.uid;
    var label = item.dataset.label;
    item.style.opacity = '0.4';
    item.style.pointerEvents = 'none';
    setTimeout(function () { removeExclusion(uid, label); }, 0);
  });

  /* ============================================================
   * Toast Notifications
   * ============================================================ */

  function showToast(message, type) {
    if (typeof ksu !== 'undefined' && typeof ksu.toast === 'function') {
      ksu.toast(message);
      return;
    }

    var container = document.getElementById('toast-container');
    if (!container) return;

    var toast = document.createElement('div');
    toast.className = 'toast' + (type ? ' ' + type : '');
    toast.textContent = message;
    container.appendChild(toast);

    setTimeout(function () {
      toast.classList.add('fade-out');
      setTimeout(function () { toast.remove(); }, 300);
    }, 2500);
  }

  /* ============================================================
   * HTML Helpers
   * ============================================================ */

  function escHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function escAttr(str) {
    return String(str).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  /* ============================================================
   * Initial Load
   * ============================================================ */

  loadStatus();

})();
