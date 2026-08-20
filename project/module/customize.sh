ui_print " "
ui_print "======================================="
ui_print "           MountZero VFS               "
ui_print "   VFS Kernel Injection Metamodule     "
ui_print "======================================="
ui_print " "

ui_print "- Device Architecture: $ARCH"

mkdir -p "$MODPATH/bin"

# Install mzctl — check arch-specific first, then generic name
if [ -f "$MODPATH/system/bin/mzctl-$ARCH" ]; then
  cp "$MODPATH/system/bin/mzctl-$ARCH" "$MODPATH/bin/mzctl"
  ui_print "- Installed mzctl binary (arch: $ARCH)"
elif [ -f "$MODPATH/system/bin/mzctl" ]; then
  cp "$MODPATH/system/bin/mzctl" "$MODPATH/bin/mzctl"
  ui_print "- Installed mzctl binary (generic)"
else
  ui_print "! No mzctl binary found, skipping"
fi

# Install susfs — check arch-specific first, then generic name
if [ -f "$MODPATH/system/bin/susfs-$ARCH" ]; then
  cp "$MODPATH/system/bin/susfs-$ARCH" "$MODPATH/bin/susfs"
  ui_print "- Installed susfs binary (arch: $ARCH)"
elif [ -f "$MODPATH/system/bin/susfs" ]; then
  cp "$MODPATH/system/bin/susfs" "$MODPATH/bin/susfs"
  ui_print "- Installed susfs binary (generic)"
fi

chmod 755 "$MODPATH/bin/mzctl" "$MODPATH/bin/susfs" 2>/dev/null
rm -rf "$MODPATH/system"

ui_print "- Checking kernel driver..."

MZCTL="$MODPATH/bin/mzctl"

# Check sysfs first (original MountZero detection method)
if [ -f /sys/kernel/mountzero/version ]; then
  VERSION=$(cat /sys/kernel/mountzero/version 2>/dev/null)
  STATUS=$(cat /sys/kernel/mountzero/status 2>/dev/null)
  ui_print "  [OK] MountZero VFS kernel driver detected via sysfs."
  ui_print "  [OK] Driver version: ${VERSION:-unknown}, Status: ${STATUS:-unknown}"
else
  ui_print "  [INFO] Kernel driver not detected during install (normal)."
  ui_print "  [INFO] Module will auto-activate on next reboot if kernel supports it."
fi

# SUSFS detection
if [ -x "$MODPATH/bin/susfs" ]; then
  SUSFS_VER=$("$MODPATH/bin/susfs" show version 2>/dev/null)
  if [ -n "$SUSFS_VER" ]; then
    ui_print "  [OK] SUSFS detected: $SUSFS_VER"
  else
    ui_print "  [WARN] SUSFS binary present but kernel support not detected."
  fi
fi

# OverlayFS detection
if mount -t overlay -o "lowerdir=/,upperdir=/dev/null,workdir=/dev/null" overlay_test /dev/null 2>/dev/null; then
  ui_print "  [OK] OverlayFS available"
  umount /dev/null 2>/dev/null
else
  ui_print "  [INFO] OverlayFS not available or not needed (VFS mode active)"
fi

# EROFS detection
if grep -q erofs /proc/filesystems 2>/dev/null; then
  ui_print "  [OK] EROFS filesystem available"
else
  ui_print "  [INFO] EROFS not detected (not required)"
fi

MZ_DATA="/data/adb/mountzero"
mkdir -p "$MZ_DATA"
rm -f "$MZ_DATA/.booting"

ui_print " "
ui_print "- Installation complete."
