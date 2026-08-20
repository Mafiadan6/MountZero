#!/system/bin/sh
# MountZero VFS - Service Script (Hot-plug daemon + overlay unmount watcher)
# Runs after boot-complete. Watches for new/removed modules.

MODDIR="${0%/*}"
CONFIG_DIR="/data/adb/mountzero"
CONFIG_SH="$MODDIR/config.sh"
BRIDGE_SH="$MODDIR/bridge.sh"
CONFIG_FILE="$CONFIG_DIR/config.toml"
WORK_BASE="/dev/mountzero_work"
UPPER_BASE="/dev/mountzero_upper"
RESETPROP="/data/adb/ksu/bin/resetprop"

# ============================================================
# Install binaries at boot (service.sh runs with full root access)
# ============================================================
install_binaries() {
    # Install mzctl - enforce 755 permissions strictly
    if [ -f "$MODDIR/bin/mzctl" ]; then
        chmod 755 "$MODDIR/bin/mzctl" 2>/dev/null
        for target in /data/adb/ksu/bin/mzctl /data/adb/ap/bin/mzctl; do
            mkdir -p "$(dirname "$target")" 2>/dev/null
            if cat "$MODDIR/bin/mzctl" > "$target" 2>/dev/null; then
                chmod 755 "$target"
                chown root:root "$target"
                chcon u:object_r:system_file:s0 "$target" 2>/dev/null || true
                # Verify permissions are correct
                local perms=$(stat -c "%a" "$target" 2>/dev/null)
                if [ "$perms" != "755" ]; then
                    chmod 755 "$target"
                fi
                echo "mountzero: mzctl installed to $target (perms: $(stat -c '%a' "$target"))" > /dev/kmsg 2>/dev/null
                break
            fi
        done
    fi

    # Install susfs - enforce 755 permissions strictly
    if [ -f "$MODDIR/bin/susfs" ]; then
        chmod 755 "$MODDIR/bin/susfs" 2>/dev/null
        for target in /data/adb/ksu/bin/susfs /data/adb/ap/bin/susfs; do
            mkdir -p "$(dirname "$target")" 2>/dev/null
            if cat "$MODDIR/bin/susfs" > "$target" 2>/dev/null; then
                chmod 755 "$target"
                chown root:root "$target"
                chcon u:object_r:system_file:s0 "$target" 2>/dev/null || true
                # Verify permissions are correct
                local perms=$(stat -c "%a" "$target" 2>/dev/null)
                if [ "$perms" != "755" ]; then
                    chmod 755 "$target"
                fi
                ln -sf "$target" /data/adb/ksu/bin/ksu_susfs 2>/dev/null || true
                ln -sf "$target" /data/adb/ap/bin/ksu_susfs 2>/dev/null || true
                echo "mountzero: susfs installed to $target (perms: $(stat -c '%a' "$target"))" > /dev/kmsg 2>/dev/null
                break
            fi
        done
    fi
}

install_binaries

# Ensure config.toml exists (creates default if missing)
if [ -x "$CONFIG_SH" ]; then
    "$CONFIG_SH" init 2>/dev/null
fi

# Wait for boot to complete
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# Use the binary from manager bin dir (or fallback to module path)
MZCTL="/data/adb/ksu/bin/mzctl"
SUSFS="/data/adb/ksu/bin/susfs"
[ -f "$MZCTL" ] || MZCTL="$MODDIR/bin/mzctl"
[ -f "$SUSFS" ] || SUSFS="$MODDIR/bin/susfs"

# Ensure MountZero is enabled
$MZCTL enable 2>/dev/null

# Apply BBR congestion control if enabled (persists across reboots)
BBR_ENABLED=$(cat /data/adb/mountzero/bbr_enabled 2>/dev/null)
if [ "$BBR_ENABLED" = "1" ]; then
    sysctl -w net.core.default_qdisc=fq 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "mountzero: BBR enabled at boot" > /dev/kmsg 2>/dev/null
fi

# Reset boot counter after successful boot
echo 0 > "$CONFIG_DIR/.bootcount" 2>/dev/null

# Reconcile external SUSFS configs on boot
if [ -x "$BRIDGE_SH" ]; then
    "$BRIDGE_SH" reconcile all 2>/dev/null
    "$BRIDGE_SH" write "$CONFIG_FILE" 2>/dev/null
fi

# Handle ADB Root
ADB_ROOT_ENABLED=$(cat /data/adb/mountzero/adb_root 2>/dev/null)
if [ "$ADB_ROOT_ENABLED" = "true" ]; then
    echo "mountzero: enabling ADB root" > /dev/kmsg 2>/dev/null
    setprop service.adb.root 1 2>/dev/null || /data/adb/ksu/bin/resetprop service.adb.root 1 2>/dev/null
fi


# ============================================================
# Auto-scan modules and create VFS rules at boot
# ============================================================
echo "mountzero: scanning modules for VFS rules..." > /dev/kmsg 2>/dev/null

for moddir in /data/adb/modules/*/; do
    [ -d "$moddir" ] || continue
    MODID=$(basename "$moddir")
    case "$MODID" in
        mountzero_vfs|meta-mountzero_vfs) continue ;;
    esac
    [ -f "${moddir}disable" ] && continue
    if [ -d "${moddir}system" ]; then
        find "${moddir}system" -type f 2>/dev/null | while read -r filepath; do
            relpath="${filepath#${moddir}system}"
            virt_path="/system${relpath}"
            $MZCTL add "$virt_path" "$filepath" 2>/dev/null
        done
        echo "mountzero: added VFS rules for module: $MODID" > /dev/kmsg 2>/dev/null
    fi
done

for moddir in /data/local/*/; do
    [ -d "$moddir" ] || continue
    MODID=$(basename "$moddir")
    case "$MODID" in
        lost+found|tmp|media|oem|vendor|system|tests|traces) continue ;;
    esac
    $MZCTL add "/data/local/${MODID}" "$moddir" 2>/dev/null
    echo "mountzero: added VFS rule for custom module: $MODID" > /dev/kmsg 2>/dev/null
done

echo "mountzero: VFS module scan complete" > /dev/kmsg 2>/dev/null

# ============================================================
# Replay excluded UIDs from persistence
# ============================================================
EXCLUSION_FILE="$CONFIG_DIR/.exclusion_list"
if [ -f "$EXCLUSION_FILE" ]; then
    while IFS= read -r uid; do
        uid=$(echo "$uid" | tr -d '[:space:]')
        [ -z "$uid" ] && continue
        $MZCTL block "$uid" 2>/dev/null
        echo "mountzero: replayed UID exclusion: $uid" > /dev/kmsg 2>/dev/null
    done < "$EXCLUSION_FILE"
fi

# ============================================================
# BRENE-compatible Root Hiding (boot-completed stage)
# Runs in background to not block hot-plug daemon
# ============================================================

(
    # Sync WebUI config → BRENE shell variables
    if [ -x "$CONFIG_SH" ]; then
        "$CONFIG_SH" init 2>/dev/null
    fi

    # Read config.toml for per-phase toggles
    CFG="$CONFIG_DIR/config.toml"
    _get_cfg() {
        local sec="$1" key="$2" def="$3"
        [ -f "$CFG" ] || { echo "$def"; return; }
        awk -F'=' -v sec="$sec" -v key="$key" -v def="$def" '
            /^\[/ { in_sec = (substr($0, 2, length($0)-2) == sec) ? 1 : 0; next }
            in_sec && $1 ~ "^ *"key" *$" { gsub(/^[ ]+|[ ]+$/, "", $2); gsub(/^["'"'"']|["'"'"']$/, "", $2); print $2; exit }
            END { if (!found) print def }
        ' "$CFG"
    }

    _hide_paths=$(_get_cfg ghost hidePaths true)
    _hide_spoof=$(_get_cfg ghost hideSpoof true)
    _hide_mounts=$(_get_cfg ghost kernelUmount true)
    _hide_lsposed=$(_get_cfg ghost hideLsposed false)
    _hide_loops=$(_get_cfg ghost hideLoops true)
    _hide_sdcard=$(_get_cfg ghost nonStandardSdcardPathsHiding false)
    _hide_sdcard_android=$(_get_cfg ghost nonStandardSdcardAndroidPathsHiding false)
    _hide_injections=$(_get_cfg ghost autoHideInjections true)
    _hide_recovery=$(_get_cfg ghost hideRecovery true)
    _hide_cleanup=$(_get_cfg ghost cleanupLeftovers false)
    _hide_inotify=$(_get_cfg ghost inotifyWatcher false)
    _hide_selinux=$(_get_cfg ghost selinuxEnforce false)

    # Apply hiding phases based on config
    if [ -f "$MODDIR/hiding.sh" ]; then
        chmod 755 "$MODDIR/hiding.sh"
        [ "$_hide_paths" = "true" ] && "$MODDIR/hiding.sh" paths 2>/dev/null
        [ "$_hide_spoof" = "true" ] && "$MODDIR/hiding.sh" spoof 2>/dev/null
        [ "$_hide_mounts" = "true" ] && "$MODDIR/hiding.sh" mounts 2>/dev/null
        [ "$_hide_lsposed" = "true" ] && "$MODDIR/hiding.sh" lsposed 2>/dev/null
        [ "$_hide_loops" = "true" ] && "$MODDIR/hiding.sh" loops 2>/dev/null
        [ "$_hide_sdcard" = "true" ] || [ "$_hide_sdcard_android" = "true" ] && "$MODDIR/hiding.sh" sdcard 2>/dev/null
        [ "$_hide_injections" = "true" ] && "$MODDIR/hiding.sh" injections 2>/dev/null
        [ "$_hide_recovery" = "true" ] && "$MODDIR/hiding.sh" recovery 2>/dev/null
        [ "$_hide_cleanup" = "true" ] && "$MODDIR/hiding.sh" cleanup 2>/dev/null
        [ "$_hide_inotify" = "true" ] && "$MODDIR/hiding.sh" inotify 2>/dev/null
        [ "$_hide_selinux" = "true" ] && "$MODDIR/hiding.sh" selinux 2>/dev/null
        echo "mountzero: hiding phases applied at boot (paths=$_hide_paths spoof=$_hide_spoof mounts=$_hide_mounts lsposed=$_hide_lsposed loops=$_hide_loops sdcard=$_hide_sdcard injections=$_hide_injections recovery=$_hide_recovery cleanup=$_hide_cleanup inotify=$_hide_inotify selinux=$_hide_selinux)" > /dev/kmsg 2>/dev/null
    fi
) &

# Function: Unmount a module's overlay partitions
unmount_module_overlays() {
    local modid="$1"

    grep "mountzero_${modid}_" /proc/mounts 2>/dev/null | while read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $2}')
        umount -l "$mp" 2>/dev/null
        echo "MountZero: unmounted overlay: $mp ($modid)" > /dev/kmsg 2>/dev/null
    done

    # Clean work/upper dirs
    rm -rf "${WORK_BASE}/${modid}_"* 2>/dev/null
    rm -rf "${UPPER_BASE}/${modid}_"* 2>/dev/null
}

# Track currently mounted modules for change detection
PREV_MODULES=$(ls -1 /data/adb/modules/ 2>/dev/null | sort)

# Hot-plug auto-detection daemon
while true; do
    # Detect newly installed modules
    CURR_MODULES=$(ls -1 /data/adb/modules/ 2>/dev/null | sort)

    # Find new modules
    for modid in $CURR_MODULES; do
        case "$modid" in
            mountzero_vfs|meta-mountzero_vfs) continue ;;
        esac

        # Check if this is a new module
        if ! echo "$PREV_MODULES" | grep -qx "$modid"; then
            echo "MountZero: New module detected: $modid" > /dev/kmsg 2>/dev/null
            moddir="/data/adb/modules/$modid"

            if [ -d "$moddir" ] && [ ! -f "${moddir}disable" ] && [ ! -f "${moddir}remove" ]; then
                $MZCTL module install "$modid" "$moddir" 2>/dev/null

                # Mount overlay if partition exists
                for part in system vendor product system_ext odm; do
                    if [ -d "${moddir}${part}" ]; then
                        mkdir -p "${WORK_BASE}/${modid}_${part}_work" 2>/dev/null
                        mkdir -p "${UPPER_BASE}/${modid}_${part}_upper" 2>/dev/null
                        mount -t overlay "mountzero_${modid}_${part}" \
                            -o "lowerdir=${moddir}${part}:/${part},upperdir=${UPPER_BASE}/${modid}_${part}_upper,workdir=${WORK_BASE}/${modid}_${part}_work" \
                            "/${part}" 2>/dev/null
                    fi
                done

                # Trigger module's own service.sh if exists (hotplug like BreZygisk)
                if [ -f "${moddir}/service.sh" ]; then
                    echo "MountZero: Triggering module service: $modid" > /dev/kmsg 2>/dev/null
                    sh "${moddir}/service.sh" &
                fi
            fi
        fi
    done

    # Find removed modules
    for modid in $PREV_MODULES; do
        case "$modid" in
            mountzero_vfs|meta-mountzero_vfs) continue ;;
        esac

        if ! echo "$CURR_MODULES" | grep -qx "$modid"; then
            echo "MountZero: Module removed: $modid" > /dev/kmsg 2>/dev/null
            unmount_module_overlays "$modid"
            $MZCTL clear 2>/dev/null
        fi
    done

    # Check for modules_update (hot install)
    if [ -d "/data/adb/modules_update" ]; then
        for moddir in /data/adb/modules_update/*/; do
            [ -d "$moddir" ] || continue
            MODID=$(basename "$moddir")
            case "$MODID" in
                mountzero_vfs|meta-mountzero_vfs) continue ;;
            esac
            if [ ! -f "$CONFIG_DIR/.mz_installed_$MODID" ]; then
                echo "MountZero: Hot-plug installing module: $MODID" > /dev/kmsg 2>/dev/null
                $MZCTL module install "$MODID" "$moddir" 2>/dev/null
                touch "$CONFIG_DIR/.mz_installed_$MODID"
            fi
        done
    fi

    # Check for new custom modules in /data/local/
    for moddir in /data/local/*/; do
        [ -d "$moddir" ] || continue
        MODID=$(basename "$moddir")
        case "$MODID" in
            lost+found|tmp|media|oem|vendor|system|tests|traces) continue ;;
        esac
        if [ ! -f "$CONFIG_DIR/.mz_installed_$MODID" ]; then
            echo "MountZero: Hot-plug installing custom module: $MODID" > /dev/kmsg 2>/dev/null
            $MZCTL module install "$MODID" "$moddir" custom 2>/dev/null
            touch "$CONFIG_DIR/.mz_installed_$MODID"
        fi
    done

    PREV_MODULES="$CURR_MODULES"
    sleep 5
done
