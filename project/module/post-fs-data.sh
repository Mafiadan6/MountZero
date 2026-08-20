#!/bin/bash
# MountZero VFS - Post-FS-Data Script
# Early boot: AVC spoofing, mount hiding from zygote, uname, cmdline, PTYs

MODDIR=${0%/*}
PATH=/data/adb/ksu/bin:$PATH
KSU_BIN=/data/adb/ksud
SUSFS_BIN=/data/adb/ksu/bin/susfs
PERSISTENT_DIR=/data/adb/mountzero
CONFIG_SH="$MODDIR/config.sh"

mkdir -p "$PERSISTENT_DIR" 2>/dev/null
true > "${PERSISTENT_DIR}/logs.txt" 2>/dev/null

# Init config (generates config_brene.sh from config.toml)
if [ -x "$CONFIG_SH" ]; then
    "$CONFIG_SH" init 2>/dev/null
fi

# Load utils
[ -f "${MODDIR}/utils.sh" ] && . "${MODDIR}/utils.sh"

# Load BRENE-style config
if [ -f "${PERSISTENT_DIR}/config_brene.sh" ]; then
    . "${PERSISTENT_DIR}/config_brene.sh"
fi

# Fallback to ksu_susfs if susfs not available
if ! command -v "$SUSFS_BIN" >/dev/null 2>&1; then
    SUSFS_BIN="/data/adb/ksu/bin/ksu_susfs"
fi

# ============================================================
# 1. AVC Log Spoofing (hide 'su' domain from /proc/<pid>)
# ============================================================
if [ "${config_enable_avc_log_spoofing}" = "1" ]; then
    ${SUSFS_BIN} enable_avc_log_spoofing 1 2>/dev/null
    echo "mountzero: avc_log_spoofing=1" > /dev/kmsg 2>/dev/null
fi

# ============================================================
# 2. Hide Suspicious Mounts for Non-SU Procs (prevent zygote caching)
# ============================================================
if [ "${config_hide_sus_mnts_for_non_su_procs}" = "1" ]; then
    # Try ksu_susfs first, then susfs
    if ${SUSFS_BIN} hide_sus_mnts_for_non_su_procs 1 2>/dev/null; then
        echo "mountzero: hide_sus_mnts_for_non_su_procs=1 via $SUSFS_BIN" > /dev/kmsg 2>/dev/null
    elif /data/adb/ksu/bin/ksu_susfs hide_sus_mnts_for_non_su_procs 1 2>/dev/null; then
        echo "mountzero: hide_sus_mnts_for_non_su_procs=1 via ksu_susfs" > /dev/kmsg 2>/dev/null
    elif susfs hide_sus_mnts_for_non_su_procs 1 2>/dev/null; then
        echo "mountzero: hide_sus_mnts_for_non_su_procs=1 via susfs" > /dev/kmsg 2>/dev/null
    else
        echo "mountzero: hide_sus_mnts_for_non_su_procs FAILED — no working susfs binary" > /dev/kmsg 2>/dev/null
    fi
fi

# ============================================================
# 3. Uname Spoofing
# ============================================================
if [ "${config_spoof_uname}" = "1" ]; then
    kernel_version=$(cat /proc/version | awk '{print $3}' | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    kmi=$(${KSU_BIN} boot-info current-kmi 2>/dev/null | cut -d'-' -f1)

    if [ -n "$kernel_version" ] && [ -n "$kmi" ]; then
        uname_kernel_release="${kernel_version}-${kmi}"
        uname_kernel_version="#1 SMP PREEMPT $(resetprop ro.build.date 2>/dev/null | tr -s ' ')"
        ${SUSFS_BIN} set_uname "${uname_kernel_release}" "${uname_kernel_version}" 2>/dev/null
        echo "mountzero: set_uname ${uname_kernel_release}" > /dev/kmsg 2>/dev/null
    fi
fi

# ============================================================
# 4. Cmdline/Bootconfig Spoofing
# ============================================================
if [ "${config_spoof_cmdline_or_bootconfig}" = "1" ]; then
    susfs_variant=$(${SUSFS_BIN} show variant 2>/dev/null)

    if [ "${susfs_variant}" = "GKI" ]; then
        FAKE_BOOTCONFIG="${PERSISTENT_DIR}/fake_bootconfig"
        cat /proc/bootconfig > "${FAKE_BOOTCONFIG}" 2>/dev/null
        sed -i 's/androidboot.warranty_bit = "1"/androidboot.warranty_bit = "0"/' "${FAKE_BOOTCONFIG}" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate = "orange"/androidboot.verifiedbootstate = "green"/' "${FAKE_BOOTCONFIG}" 2>/dev/null
        ${SUSFS_BIN} set_cmdline_or_bootconfig "${FAKE_BOOTCONFIG}" 2>/dev/null
        echo "mountzero: cmdline GKI spoofed" > /dev/kmsg 2>/dev/null
    else
        FAKE_CMDLINE="${PERSISTENT_DIR}/fake_cmdline"
        cat /proc/cmdline > "${FAKE_CMDLINE}" 2>/dev/null
        sed -i 's/androidboot.warranty_bit=1/androidboot.warranty_bit=0/' "${FAKE_CMDLINE}" 2>/dev/null
        sed -i 's/androidboot.verifiedbootstate=orange/androidboot.verifiedbootstate=green/' "${FAKE_CMDLINE}" 2>/dev/null
        ${SUSFS_BIN} set_cmdline_or_bootconfig "${FAKE_CMDLINE}" 2>/dev/null
        echo "mountzero: cmdline non-GKI spoofed" > /dev/kmsg 2>/dev/null
    fi
fi

# ============================================================
# 5. Hide Suspicious PTYs
# ============================================================
if [ "${config_hide_suspicious_pty}" = "1" ]; then
    for i in $(seq 0 5); do
        [ -e "/dev/pts/$i" ] && ${SUSFS_BIN} add_sus_path_loop "/dev/pts/$i" 2>/dev/null
    done
    echo "mountzero: PTYs hidden" > /dev/kmsg 2>/dev/null
fi

# ============================================================
# 6. SUSFS kernel log
# ============================================================
if [ "${config_enable_log}" = "1" ]; then
    ${SUSFS_BIN} enable_log 1 2>/dev/null
fi

# ============================================================
# 7. Kernel umount for suspicious overlay mounts (backup defense)
# ============================================================
if [ "${config_umount_suspicious_mounts}" = "1" ]; then
    $KSU_BIN kernel notify-module-mounted 2>/dev/null
    cat /proc/1/mountinfo 2>/dev/null | grep "overlay" | grep -E "/(product|system)/(app|priv-app|etc|etc/permissions|etc/sysconfig|framework|media|lib|usr|vendor/(app|etc|overlay))" | awk '{print $5}' | while read -r mount; do
        $KSU_BIN kernel umount add -f 2 "$mount" 2>/dev/null
    done
    echo "mountzero: kernel_umount overlay mounts done" > /dev/kmsg 2>/dev/null
fi

echo "mountzero: post-fs-data.sh done" > /dev/kmsg 2>/dev/null
exit 0
