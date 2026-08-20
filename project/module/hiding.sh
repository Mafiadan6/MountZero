#!/system/bin/sh
# MountZero VFS - SUSFS Hiding Engine (BRENE-compatible)
# Provides root evasion: path hiding, maps hiding, prop spoofing, cmdline spoofing
# Based on BRENE by rrr333nnn333

MODDIR="${0%/*}"
PATH=/data/adb/ksu/bin:$PATH
KSU_BIN=/data/adb/ksud
KSU_MODULES_DIR=/data/adb/modules
SUSFS_BIN=/data/adb/ksu/bin/susfs
RESETPROP=/data/adb/ksu/bin/resetprop
PERSISTENT_DIR=/data/adb/mountzero
DEST_BIN_DIR=/data/adb/ksu/bin
LOG_FILE="$PERSISTENT_DIR/logs.txt"
CUSTOM_ROM_NAMES="lineage|infinity|evolution|crdroid|mistos|axon|pixelos|rising|lunaris|halcyon|havoc|alphadroid|bliss|calyx|derpfact|graphene|lmodroid|lumine|matrixx|clover|yaap|aospa"

mkdir -p "$PERSISTENT_DIR" 2>/dev/null

mkdir -p "$PERSISTENT_DIR" 2>/dev/null
mkdir -p "$PERSISTENT_DIR/logs" 2>/dev/null

# Load config
if [ -f "$PERSISTENT_DIR/config_brene.sh" ]; then
    . "$PERSISTENT_DIR/config_brene.sh"
fi

# Fallback to ksu_susfs if susfs not available
if ! command -v "$SUSFS_BIN" >/dev/null 2>&1; then
    SUSFS_BIN="/data/adb/ksu/bin/ksu_susfs"
fi

# ============================================================
# Logging (writes to logs.txt for WebUI + kmsg for kernel log)
# ============================================================

init_log() {
    echo "========================================" > "$LOG_FILE"
    echo "MountZero Hiding Log" >> "$LOG_FILE"
    echo "Time: $(date)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
}

log() {
    echo "$*" >> "$LOG_FILE" 2>/dev/null
    echo "mountzero-hiding: $*" > /dev/kmsg 2>/dev/null
}

log_ok() {
    log "[OK] $*"
}

log_fail() {
    log "[FAIL] $*"
}

log_info() {
    log "[INFO] $*"
}

# ============================================================
# Utility functions (BRENE-compatible)
# ============================================================

susfs_clone_perm() {
    local TO="$1"
    local FROM="$2"
    [ -z "$TO" ] || [ -z "$FROM" ] && return
    local CLONED_PERM_STRING
    CLONED_PERM_STRING=$(stat -c "%a %U %G" "$FROM" 2>/dev/null)
    [ -z "$CLONED_PERM_STRING" ] && return
    set $CLONED_PERM_STRING
    chmod $1 "$TO" 2>/dev/null
    chown $2:$3 "$TO" 2>/dev/null
    busybox chcon --reference="$FROM" "$TO" 2>/dev/null
}

resetprop_n() {
    $RESETPROP -n "$1" "$2" 2>/dev/null
}

if_prop_value_exits_resetprop_n() {
    local PROP_NAME=$1
    local EXPECTED_VALUE=$2
    local CURRENT_VALUE
    CURRENT_VALUE=$($RESETPROP "$PROP_NAME" 2>/dev/null)
    [ -z "$CURRENT_VALUE" ] || [ "$CURRENT_VALUE" = "$EXPECTED_VALUE" ] && return
    $RESETPROP -n "$PROP_NAME" "$EXPECTED_VALUE" 2>/dev/null
}

brene_sus_path() {
    $SUSFS_BIN add_sus_path "$1" 2>/dev/null && \
        log_ok "sus_path: $1" || \
        log_fail "sus_path: $1"
}

brene_sus_path_loop() {
    $SUSFS_BIN add_sus_path_loop "$1" 2>/dev/null && \
        log_ok "sus_path_loop: $1" || \
        log_fail "sus_path_loop: $1"
}

brene_sus_map() {
    $SUSFS_BIN add_sus_map "$1" 2>/dev/null && \
        log_ok "sus_map: $1" || \
        log_fail "sus_map: $1"
}

brene_set_uname() {
    $SUSFS_BIN set_uname "$1" "$2" 2>/dev/null && \
        log_ok "set_uname: $1 $2" || \
        log_fail "set_uname: $1 $2"
}

brene_sus_mount() {
    $KSU_BIN kernel notify-module-mounted 2>/dev/null
    $KSU_BIN kernel umount add -f 2 "$1" 2>/dev/null
}

# ============================================================
# Phase: paths — Hide common detection paths
# ============================================================

hide_paths() {
    log_info "Phase: paths — hiding common detection paths"

    # LSPosed/Zygisk injection paths
    for moddir in "$KSU_MODULES_DIR"/*; do
        [ -d "$moddir" ] || continue
        local modid=$(basename "$moddir")
        [ -f "${moddir}disable" ] && continue
        [ -d "${moddir}system" ] || continue

        log_info "Scanning module: $modid"

        # Hide module system files from /proc maps
        find "${moddir}/system" -type f 2>/dev/null | while read -r filepath; do
            brene_sus_map "$filepath"
        done

        # Hide module .so files specifically
        find "${moddir}" -name "*.so" 2>/dev/null | while read -r so_file; do
            brene_sus_map "$so_file"
        done
    done

    # Hide common tool paths
    for path in \
        "/data/adb/magisk" \
        "/data/adb/modules" \
        "/data/adb/modules_update" \
        "/data/adb/service.d" \
        "/data/adb/post-fs-data.d" \
        "/data/adb/ksu" \
        "/data/adb/ap" \
        "/data/adb/mountzero" \
        "/data/adb/lspd" \
        "/data/adb/lspd/config" \
        "/data/adb/lspd/framework" \
        "/data/adb/lspd/lib" \
        "/data/adb/lspd/log" \
        "/data/adb/lspd/manager" \
        "/data/adb/lspd/misc" \
        "/data/adb/lspd/modules" \
        "/data/adb/lspd/plugin" \
        "/data/adb/lspd/toggle" \
        "/dev/ksu" \
        "/dev/ksud" \
        "/dev/ap" \
        "/dev/susfs" \
        "/dev/mountzero" \
        "/dev/mountzero_work" \
        "/dev/mountzero_upper" \
        "/proc/ksu" \
        "/proc/susfs" \
        "/system/bin/su" \
        "/system/xbin/su" \
        "/system/bin/.ext" \
        "/system/usr/izane.dat" \
        "/cache/su" \
        "/data/su" \
        "/data/data/com.topjohnwu.magisk" \
        "/data/user_de/com.topjohnwu.magisk" \
        "/data/adb/ksu/bin" \
        "/data/adb/ksu/modules" \
        "/data/adb/ksu/last_kmsg" \
        "/data/adb/ksu/log" \
        "/data/adb/ksu/susfs" \
        "/data/adb/modules/lsposed" \
        "/data/adb/modules/zygisk_lsposed" \
        "/data/adb/modules/zygisksu" \
        "/data/adb/modules/zygisk_next" \
        "/data/adb/modules/zygisk" \
        "/data/adb/modules/shamiko" \
        "/data/adb/modules/zylisk" \
        "/data/adb/modules/playintegrityfix" \
        "/data/adb/modules/marketfix" \
        "/data/adb/modules/lspd" \
        "/data/adb/modules/lspatch" \
        "/data/adb/modules/xposed" \
        "/data/adb/modules/wa_enhancer" \
        "/data/adb/modules/televip" \
        "/data/data/com.wmods.wppenhacer" \
        "/data/user_de/com.wmods.wppenhacer" \
        "/data/data/com.my.televip" \
        "/data/user_de/com.my.televip" \
        "/data/app/*/com.wmods.wppenhacer*" \
        "/data/app/*/com.my.televip*" \
        "/data/app/*/org.lsposed.manager*" \
        "/data/app/*/org.lsposed.lspatch*"
    do
        [ -e "$path" ] && brene_sus_path "$path"
    done

    log_ok "Phase: paths complete"
}

# ============================================================
# Phase: spoof — Uname + cmdline + prop spoofing
# ============================================================

hide_spoof() {
    log_info "Phase: spoof — uname, cmdline, properties"

    # Uname spoofing
    local kernel_version
    kernel_version=$(cat /proc/version 2>/dev/null | awk '{print $3}' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    local kmi
    kmi=$($KSU_BIN boot-info current-kmi 2>/dev/null | cut -d'-' -f1)

    if [ -n "$kernel_version" ] && [ -n "$kmi" ]; then
        local uname_kernel_release="${kernel_version}-${kmi}"
        local uname_kernel_version="#1 SMP PREEMPT $($RESETPROP ro.build.date 2>/dev/null | tr -s ' ')"
        brene_set_uname "$uname_kernel_release" "$uname_kernel_version"
    fi

    # Spoof /proc/cmdline or /proc/bootconfig
    local susfs_variant
    susfs_variant=$($SUSFS_BIN show variant 2>/dev/null)

    if [ "$susfs_variant" = "GKI" ]; then
        local FAKE_BOOTCONFIG="$PERSISTENT_DIR/fake_bootconfig"
        cat /proc/bootconfig > "$FAKE_BOOTCONFIG" 2>/dev/null
        sed -i 's/androidboot.warranty_bit = "1"/androidboot.warranty_bit = "0"/' "$FAKE_BOOTCONFIG" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate = "orange"/androidboot.verifiedbootstate = "green"/' "$FAKE_BOOTCONFIG" 2>/dev/null
        $SUSFS_BIN set_cmdline_or_bootconfig "$FAKE_BOOTCONFIG" 2>/dev/null && \
            log_ok "cmdline_or_bootconfig: GKI bootconfig spoofed" || \
            log_fail "cmdline_or_bootconfig: GKI bootconfig"
    else
        local FAKE_CMDLINE="$PERSISTENT_DIR/fake_cmdline"
        cat /proc/cmdline > "$FAKE_CMDLINE" 2>/dev/null
        sed -i 's/androidboot.warranty_bit=1/androidboot.warranty_bit=0/' "$FAKE_CMDLINE" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate=orange/androidboot.verifiedbootstate=green/' "$FAKE_CMDLINE" 2>/dev/null
        $SUSFS_BIN set_cmdline_or_bootconfig "$FAKE_CMDLINE" 2>/dev/null && \
            log_ok "cmdline_or_bootconfig: cmdline spoofed" || \
            log_fail "cmdline_or_bootconfig: cmdline"
    fi

    # System properties spoofing
    resetprop_n "init.svc.adbd" "stopped"
    resetprop_n "init.svc_debug_pid.adbd" ""
    resetprop_n "persist.sys.usb.config" "mtp"
    resetprop_n "ro.adb.secure" "1"
    resetprop_n "ro.crypto.state" "encrypted"
    resetprop_n "ro.debuggable" "0"
    resetprop_n "ro.force.debuggable" "0"
    resetprop_n "ro.secure" "1"
    resetprop_n "ro.secureboot.lockstate" "locked"
    resetprop_n "ro.is_ever_orange" "0"
    resetprop_n "ro.bootmode" "normal"
    resetprop_n "ro.bootimage.build.tags" "release-keys"
    resetprop_n "ro.build.type" "user"
    resetprop_n "ro.build.tags" "release-keys"
    resetprop_n "vendor.boot.vbmeta.device_state" "locked"
    resetprop_n "vendor.boot.verifiedbootstate" "green"
    resetprop_n "ro.boot.flash.locked" "1"
    resetprop_n "ro.boot.realme.lockstate" "1"
    resetprop_n "ro.boot.realmebootstate" "green"
    resetprop_n "ro.boot.verifiedbooterror" ""
    resetprop_n "ro.boot.verifiedbootstate" "green"
    resetprop_n "ro.boot.veritymode" "enforcing"
    resetprop_n "ro.boot.veritymode.managed" "yes"
    resetprop_n "ro.boot.vbmeta.size" "4096"
    resetprop_n "ro.boot.vbmeta.hash_alg" "sha256"
    resetprop_n "ro.boot.vbmeta.avb_version" "1.3"
    resetprop_n "ro.boot.vbmeta.device_state" "locked"
    resetprop_n "ro.boot.vbmeta.invalidate_on_error" "yes"

    if_prop_value_exits_resetprop_n "ro.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.vendor.boot.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.vendor.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.boot.warranty_bit" "0"

    # Fix fingerprint
    local fingerprint_value
    fingerprint_value=$($RESETPROP ro.build.fingerprint 2>/dev/null)
    if [ -n "$fingerprint_value" ]; then
        local new_fingerprint_value="${fingerprint_value//userdebug/user}"
        resetprop_n "ro.bootimage.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.odm.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.odm_dlkm.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.product.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.system.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.system_dlkm.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.system_ext.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.vendor.build.fingerprint" "$new_fingerprint_value"
        resetprop_n "ro.vendor_dlkm.build.fingerprint" "$new_fingerprint_value"
    fi

    # Sync build dates
    local new_utc_value
    new_utc_value=$($RESETPROP ro.build.date.utc 2>/dev/null)
    if [ -n "$new_utc_value" ]; then
        resetprop_n "ro.bootimage.build.date.utc" "$new_utc_value"
        resetprop_n "ro.build.date.utc" "$new_utc_value"
        resetprop_n "ro.odm.build.date.utc" "$new_utc_value"
        resetprop_n "ro.odm_dlkm.build.date.utc" "$new_utc_value"
        resetprop_n "ro.product.build.date.utc" "$new_utc_value"
        resetprop_n "ro.system.build.date.utc" "$new_utc_value"
        resetprop_n "ro.system_dlkm.build.date.utc" "$new_utc_value"
        resetprop_n "ro.system_ext.build.date.utc" "$new_utc_value"
        resetprop_n "ro.vendor.build.date.utc" "$new_utc_value"
        resetprop_n "ro.vendor_dlkm.build.date.utc" "$new_utc_value"
    fi

    # Delete detection props
    $RESETPROP --delete "ro.boot.verifiedbooterror" 2>/dev/null
    $RESETPROP --delete "ro.boot.verifyerrorpart" 2>/dev/null
    $RESETPROP --delete "crashrecovery.rescue_boot_count" 2>/dev/null
    $RESETPROP --delete "service.adb.root" 2>/dev/null
    $RESETPROP --delete "service.adb.tcp.port" 2>/dev/null
    $RESETPROP --delete "init.svc.magisk" 2>/dev/null
    $RESETPROP --delete "init.svc.magisk_patcher" 2>/dev/null

    # SDK version check
    local sdk
    sdk=$($RESETPROP ro.build.version.sdk 2>/dev/null)
    if [ -n "$sdk" ] && [ "$sdk" -ge 36 ] 2>/dev/null; then
        $RESETPROP --delete "sys.oem_unlock_allowed" 2>/dev/null
    else
        resetprop_n "sys.oem_unlock_allowed" "0"
    fi

    $RESETPROP -c --force 2>/dev/null
    log_ok "Phase: spoof complete"
}

# ============================================================
# Phase: mounts — Hide suspicious mounts via kernel umount
# ============================================================

hide_mounts() {
    log_info "Phase: mounts — hiding suspicious mounts"

    $KSU_BIN kernel notify-module-mounted 2>/dev/null

    # Kernel-umount overlay mounts at suspicious system paths
    # These are KSU module overlays that detection apps flag
    cat /proc/1/mountinfo 2>/dev/null | grep "overlay" | grep -E "/(product|system)/(app|priv-app|etc|etc/permissions|etc/sysconfig|framework|media|lib|usr|vendor/(app|etc|overlay))" | awk '{print $5}' | while read -r mount; do
        $KSU_BIN kernel umount add -f 2 "$mount" 2>/dev/null && \
            log_ok "kernel_umount: $mount" || \
            log_fail "kernel_umount: $mount"
    done

    # Also catch any high-ID mounts or KSU-tagged entries (BRENE pattern)
    cat /proc/1/mountinfo 2>/dev/null | grep -E "^2[0-9]{9,} .*$|KSU" | awk '{print $5}' | while read -r mount; do
        $KSU_BIN kernel umount add -f 2 "$mount" 2>/dev/null && \
            log_ok "kernel_umount: $mount" || \
            log_fail "kernel_umount: $mount"
    done

    log_ok "Phase: mounts complete"
}

# ============================================================
# Phase: lsposed — Hide LSPosed injection traces
# ============================================================

hide_lsposed() {
    log_info "Phase: lsposed — hiding LSPosed injection traces"

    # Hide LSPosed data directories
    for path in \
        "/data/adb/lspd" \
        "/data/adb/lspd/config" \
        "/data/adb/lspd/framework" \
        "/data/adb/lspd/lib" \
        "/data/adb/lspd/log" \
        "/data/adb/lspd/manager" \
        "/data/adb/lspd/misc" \
        "/data/adb/lspd/modules" \
        "/data/adb/lspd/plugin" \
        "/data/adb/lspd/toggle" \
        "/data/adb/modules/lsposed" \
        "/data/adb/modules/zygisk_lsposed" \
        "/data/adb/modules/zygisksu" \
        "/data/adb/modules/zygisk_next" \
        "/data/adb/modules/zygisk" \
        "/data/adb/modules/zygisksu" \
        "/data/adb/modules/zygisk_lsposed" \
        "/data/adb/modules/zygisk" \
        "/data/adb/modules/zygisksu" \
        "/data/adb/modules/shamiko" \
        "/data/adb/modules/zylisk" \
        "/data/adb/modules/playintegrityfix" \
        "/data/adb/modules/marketfix" \
        "/data/adb/modules/lspd" \
        "/data/adb/modules/lspatch" \
        "/data/adb/modules/xposed" \
        "/data/adb/modules/wa_enhancer" \
        "/data/adb/modules/televip" \
        "/data/data/com.wmods.wppenhacer" \
        "/data/user_de/com.wmods.wppenhacer" \
        "/data/data/com.my.televip" \
        "/data/user_de/com.my.televip" \
        "/data/app/*/com.wmods.wppenhacer*" \
        "/data/app/*/com.my.televip*" \
        "/data/app/*/org.lsposed.manager*" \
        "/data/app/*/org.lsposed.lspatch*" \
        "/data/app/*/com.wmods.lspeed*" \
        "/system/framework/XposedBridge.jar" \
        "/system/lib/libxposed_art.so" \
        "/system/lib64/libxposed_art.so" \
        "/data/dalvik-cache" \
        "/data/misc/profiles/ref" \
        "/data/misc/profiles/cur" \
        "/data/misc/lspd" \
        "/data/misc/lsposed" \
        "/data/adb/ksu/modules/lsposed" \
        "/data/adb/ksu/modules/zygisksu" \
        "/data/adb/ksu/modules/zygisk_lsposed" \
        "/data/adb/modules/disabled"
    do
        [ -e "$path" ] && brene_sus_path "$path"
    done

    # Hide LSPosed manager app data (app data directories)
    for pkg in \
        "org.lsposed.manager" \
        "org.lsposed.lspatch" \
        "com.wmods.wppenhacer" \
        "com.my.televip" \
        "com.wmods.lspeed" \
        "io.github.chsbuffer.revancedxposed" \
        "com.chsbuffer.xposed"
    do
        for base in "/data/data" "/data/user_de" "/data/user/0" "/data/user/10" "/data/user/11" "/data/user/12"; do
            [ -d "${base}/${pkg}" ] && brene_sus_path "${base}/${pkg}"
        done
        # Hide from PackageManager inventory
        pm hide "$pkg" 2>/dev/null
    done

    # Hide LSPosed manager APK from PackageManager (prevents "Installed managers" detection)
    for pkg in \
        "org.lsposed.manager" \
        "org.lsposed.lspatch" \
        "io.github.chsbuffer.revancedxposed" \
        "com.chsbuffer.xposed"
    do
        pm suspend "$pkg" 2>/dev/null
        # Also hide the APK directory from package scanning
        find /data/app -maxdepth 3 -type d -name "*${pkg}*" 2>/dev/null | while read -r d; do
            brene_sus_path "$d"
        done
    done

    # Hide EdXposed/ReVanced Xposed app installs from maps (resolve actual paths)
    find /data/app -name "base.apk" 2>/dev/null | while read -r apk; do
        if echo "$apk" | grep -qiE "revancedxposed|chsbuffer|xposed"; then
            brene_sus_map "$apk"
            brene_sus_path "$apk"
            log_ok "sus_map+path: $apk"
        fi
    done

    # Hide EdXposed/ReVanced Xposed directories
    find /data/app -maxdepth 3 -type d 2>/dev/null | while read -r d; do
        if echo "$d" | grep -qiE "revancedxposed|chsbuffer"; then
            brene_sus_path "$d"
        fi
    done

    # Hide module .so files from maps (LSPosed injection)
    for moddir in "$KSU_MODULES_DIR"/*; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        find "${moddir}" -name "*.so" 2>/dev/null | while read -r so_file; do
            brene_sus_map "$so_file"
        done
        # Hide module APK files from maps
        find "${moddir}" -name "*.apk" 2>/dev/null | while read -r apk_file; do
            brene_sus_map "$apk_file"
        done
        # Hide module dex files from maps
        find "${moddir}" -name "*.dex" 2>/dev/null | while read -r dex_file; do
            brene_sus_map "$dex_file"
        done
        # Hide module oat/vdex files
        find "${moddir}" \( -name "*.oat" -o -name "*.vdex" -o -name "*.odex" \) 2>/dev/null | while read -r f; do
            brene_sus_map "$f"
        done
    done

    # Hide LSPosed framework files from maps
    for f in \
        "/data/adb/lspd/framework"/*.jar \
        "/data/adb/lspd/lib"/*.so
    do
        [ -e "$f" ] && brene_sus_map "$f"
    done

    # Spoof LSPosed-related properties (detectors check these)
    resetprop_n "init.svc.lsposed" ""
    resetprop_n "init.svc.lsposedd" ""
    resetprop_n "sys.lspd.enabled" ""
    resetprop_n "sys.lspd.injected" ""
    resetprop_n "persist.sys.lspd.enabled" ""
    resetprop_n "ro.lspd.enabled" ""
    resetprop_n "init.svc.zygisk" ""
    resetprop_n "persist.sys.zygisk" ""

    # Clean environment variables that leak LSPosed/Xposed (detectors scan env)
    local clean_classpath=$(echo "${CLASSPATH:-}" | tr ':' '\n' | grep -viE "xposed|lspd|lsposed|edsposed|revanced|hook" | tr '\n' ':' | sed 's/:$//')
    resetprop_n "CLASSPATH" "$clean_classpath" 2>/dev/null

    local clean_bootclasspath=$(echo "${BOOTCLASSPATH:-}" | tr ':' '\n' | grep -viE "xposed|lspd|lsposed|edsposed|revanced|hook" | tr '\n' ':' | sed 's/:$//')
    resetprop_n "BOOTCLASSPATH" "$clean_bootclasspath" 2>/dev/null

    # Clear LSPosed env vars
    for ev in LSPOSED_HOME LSPOSED_DATA LSPOSED_MODULE_PARENT ANDROID_SDK_EXTENDED_HOME; do
        resetprop_n "$ev" "" 2>/dev/null
    done

    # Hide LSPosed files via susfs
    for f in \
        "/data/adb/lspd" \
        "/data/adb/lspd/config.xml" \
        "/data/adb/lspd/config/enabled_modules.list" \
        "/data/adb/lspd/config/modules.list" \
        "/data/adb/lspd/config/use_whitelist" \
        "/data/adb/lspd/log" \
        "/data/adb/lspd/framework/XposedBridge.jar"
    do
        [ -e "$f" ] && ${SUSFS_BIN} add_sus_kstat_statically "$f" 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 'default' 2>/dev/null
    done

    # Hide /proc/<pid>/maps entries for common LSPosed/Xposed libraries
    for lib in \
        "liblspd.so" \
        "libxposed_art.so" \
        "libxposed_art_`uname -m`.so" \
        "XposedBridge.jar" \
        "liblspd_hook.so" \
        "libzygisk.so" \
        "libshamiko.so"
    do
        ${SUSFS_BIN} add_sus_map "$lib" 2>/dev/null
    done

    log_ok "Phase: lsposed complete"
}

# ============================================================
# Phase: loops — Hide suspicious /dev/pts, loop devices
# ============================================================

hide_loops() {
    log_info "Phase: loops — hiding suspicious PTYs and loop devices"

    for i in $(seq 0 10); do
        [ -e "/dev/pts/$i" ] && brene_sus_path_loop "/dev/pts/$i"
    done

    # Hide loop devices
    for i in $(seq 0 15); do
        [ -e "/dev/block/loop$i" ] && brene_sus_path "/dev/block/loop$i"
    done

    # Hide suspicious char/block devices
    for path in \
        "/dev/ksu" \
        "/dev/ksud" \
        "/dev/ap" \
        "/dev/susfs" \
        "/dev/mountzero" \
        "/dev/mountzero_work" \
        "/dev/mountzero_upper"
    do
        [ -e "$path" ] && brene_sus_path "$path"
    done

    log_ok "Phase: loops complete"
}

# ============================================================
# Phase: sdcard — Hide non-standard sdcard paths
# ============================================================

hide_sdcard() {
    log_info "Phase: sdcard — hiding non-standard sdcard paths"

    local standard_paths="Alarms Android Audiobooks DCIM Documents Download Movies Music Notifications Pictures Podcasts Recordings Ringtones Android data media obb"

    # Non-standard /sdcard
    for i in /sdcard/*; do
        [ -e "$i" ] || continue
        local pass=0
        for x in $standard_paths; do
            [ "/sdcard/${x}" = "$i" ] && pass=1 && break
        done
        [ "$pass" = "1" ] && continue
        brene_sus_path_loop "$i"
    done

    # Non-standard /sdcard/Android
    local standard_android="data media obb"
    for i in /sdcard/Android/*; do
        [ -e "$i" ] || continue
        local pass=0
        for x in $standard_android; do
            [ "/sdcard/Android/${x}" = "$i" ] && pass=1 && break
        done
        [ "$pass" = "1" ] && continue
        brene_sus_path_loop "$i"
    done

    # Rooted app folders in Android/data/media/obb
    for pkg in io.github.muntashirakon.AppManager com.github.capntrips.kernelflasher com.machiav3lli.backup; do
        for sub in data media obb; do
            local full_path="/sdcard/Android/${sub}/${pkg}"
            [ -e "$full_path" ] && brene_sus_path_loop "$full_path"
        done
    done

    # Hide custom recovery paths
    [ -e "/sdcard/Fox" ] && brene_sus_path_loop "/sdcard/Fox"
    [ -e "/sdcard/TWRP" ] && brene_sus_path_loop "/sdcard/TWRP"
    [ -e "/data/recovery" ] && brene_sus_path_loop "/data/recovery"

    log_ok "Phase: sdcard complete"
}

# ============================================================
# Phase: injections — Hide module injection .so files
# ============================================================

hide_injections() {
    log_info "Phase: injections — hiding module .so injections"

    for moddir in "$KSU_MODULES_DIR"/*; do
        [ -d "$moddir" ] || continue
        local modid=$(basename "$moddir")
        [ -f "${moddir}disable" ] && continue

        # Hide system overlay files
        if [ -d "${moddir}/system" ]; then
            find "${moddir}/system" -type f 2>/dev/null | while read -r filepath; do
                brene_sus_map "$filepath"
            done
        fi

        # Hide all .so files
        find "${moddir}" -name "*.so" 2>/dev/null | while read -r so_file; do
            brene_sus_map "$so_file"
        done

        log_ok "Module injections hidden: $modid"
    done

    log_ok "Phase: injections complete"
}

# ============================================================
# Phase: recovery — Hide recovery paths
# ============================================================

hide_recovery() {
    log_info "Phase: recovery — hiding recovery paths"

    for path in \
        "/sdcard/Fox" \
        "/sdcard/TWRP" \
        "/data/recovery" \
        "/data/media/0/TWRP" \
        "/data/media/0/Fox" \
        "/cache/recovery" \
        "/cache/TWRP" \
        "/cache/Fox"
    do
        [ -e "$path" ] && brene_sus_path_loop "$path"
    done

    log_ok "Phase: recovery complete"
}

# ============================================================
# Phase: cleanup — Remove leftover detection files
# ============================================================

hide_cleanup() {
    log_info "Phase: cleanup — removing leftover detection files"

    rm -rf "/sdcard/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/data/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/media/..5.u.S" 2>/dev/null
    rm -rf "/sdcard/Android/obb/..5.u.S" 2>/dev/null

    # Remove Magisk traces
    rm -rf /data/adb/magisk.db 2>/dev/null
    rm -rf /data/adb/magisk_config 2>/dev/null
    rm -rf /data/adb/magisk.log 2>/dev/null
    rm -rf /data/adb/magisk 2>/dev/null

    # Fix /data/local/tmp
    local target_folder="/data/local/tmp"
    mkdir -p "$target_folder" 2>/dev/null
    chmod 0771 "$target_folder" 2>/dev/null
    chown shell:shell "$target_folder" 2>/dev/null
    chcon u:object_r:shell_data_file:s0 "$target_folder" 2>/dev/null
    $SUSFS_BIN add_sus_kstat_statically "$target_folder" '100' 'default' 'default' '4096' 'default' 'default' 'default' 'default' 'default' 'default' '8' '512' 2>/dev/null && \
        log_ok "data_local_tmp stat spoofed" || \
        log_fail "data_local_tmp stat spoof"

    # Hide addon.d
    [ -e "/system/addon.d" ] && brene_sus_path "/system/addon.d"

    # Hide install-recovery.sh
    [ -e "/vendor/bin/install-recovery.sh" ] && brene_sus_path "/vendor/bin/install-recovery.sh"
    [ -e "/system/bin/install-recovery.sh" ] && brene_sus_path "/system/bin/install-recovery.sh"

    log_ok "Phase: cleanup complete"
}

# ============================================================
# Phase: inotify — Start inotify watcher for ..5.u.S cleanup
# ============================================================

hide_inotify() {
    log_info "Phase: inotify — starting watcher"

    # Kill existing watcher
    killall inotifyd 2>/dev/null

    if [ -f "$MODDIR/inotify.sh" ]; then
        inotifyd "$MODDIR/inotify.sh" /sdcard:n &
        log_ok "inotify watcher started"
    else
        log_fail "inotify.sh not found"
    fi

    log_ok "Phase: inotify complete"
}

# ============================================================
# Phase: selinux — Force SELinux enforcing
# ============================================================

hide_selinux() {
    log_info "Phase: selinux — enforcing"

    # SELinux enforcing
    [ "$(getenforce 2>/dev/null)" != "Enforcing" ] && setenforce 1 2>/dev/null

    # Hide su domain from AVC logs
    $SUSFS_BIN enable_avc_log_spoofing 1 2>/dev/null && \
        log_ok "avc_log_spoofing: 1" || \
        log_fail "avc_log_spoofing"

    # KSU features
    $KSU_BIN feature set su_compat 1 2>/dev/null && \
        log_ok "KSU feature: su_compat=1" || \
        log_fail "KSU feature: su_compat"

    $KSU_BIN feature set kernel_umount 1 2>/dev/null && \
        log_ok "KSU feature: kernel_umount=1" || \
        log_fail "KSU feature: kernel_umount"

    $KSU_BIN feature set selinux_hide 1 2>/dev/null && \
        log_ok "KSU feature: selinux_hide=1" || \
        log_fail "KSU feature: selinux_hide"

    $KSU_BIN feature save 2>/dev/null

    log_ok "Phase: selinux complete"
}

# ============================================================
# Main Entry Point — Only when executed directly (not sourced)
# ============================================================

if [ "$(basename "$0")" = "hiding.sh" ] || [ "$0" = "$MODDIR/hiding.sh" ] || [ -n "$1" ]; then
    init_log

    MODE="${1:-full}"

    case "$MODE" in
    paths)
        hide_paths
        ;;
    spoof)
        hide_spoof
        ;;
    mounts)
        hide_mounts
        ;;
    lsposed)
        hide_lsposed
        ;;
    loops)
        hide_loops
        ;;
    sdcard)
        hide_sdcard
        ;;
    injections)
        hide_injections
        ;;
    recovery)
        hide_recovery
        ;;
    cleanup)
        hide_cleanup
        ;;
    inotify)
        hide_inotify
        ;;
    selinux)
        hide_selinux
        ;;
    pfd)
        hide_spoof
        hide_loops
        ;;
    bootcompleted)
        hide_paths
        hide_sdcard
        hide_injections
        hide_lsposed
        hide_recovery
        hide_cleanup
        hide_mounts
        hide_inotify
        ;;
    props)
        hide_spoof
        ;;
    full)
        hide_paths
        hide_spoof
        hide_mounts
        hide_lsposed
        hide_loops
        hide_sdcard
        hide_injections
        hide_recovery
        hide_cleanup
        hide_selinux
        ;;
    *)
        echo "Usage: $0 {paths|spoof|mounts|lsposed|loops|sdcard|injections|recovery|cleanup|inotify|selinux|pfd|bootcompleted|props|full}"
        exit 1
        ;;
esac

echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "MountZero Hiding Complete: $(date)" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

    log "Done: $MODE"
fi
