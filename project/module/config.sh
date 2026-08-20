#!/system/bin/sh
# MountZero VFS - Config Manager
# Handles config.toml read/write, defaults, and validation

CONFIG_DIR="/data/adb/mountzero"
CONFIG_FILE="$CONFIG_DIR/config.toml"

init_config() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR/logs"

    if [ -f "$CONFIG_FILE" ]; then
        return 0
    fi

    cat > "$CONFIG_FILE" << 'TOML'
# MountZero VFS Configuration
# Generated automatically on first boot

[mount]
mountEngine = "vfs"          # vfs, overlay, magic
mountSource = "KSU"          # KSU, APatch, Magisk
overlayPreferred = false
ext4ImageSizeMB = 512
randomMountPaths = true
excludeHostsModules = []

[partitions]
extra = ["product", "system_ext", "vendor"]

[susfs]
enabled = true
pathHide = true
mapsHide = true
kstat = true
susfsLog = false
avcLogSpoofing = true
hiddenPaths = []
hiddenMaps = []

[brene]
verifiedBootHash = ""
kernelUmount = false
tryUmount = false
emulateVoldAppData = false
autoHideApk = false
autoHideFonts = false
autoHideRootedFolders = false
hideSusMounts = true
forceHideLsposed = false
spoofCmdline = true
hideKsuLoops = true
propSpoofing = true
autoHideInjections = true
toggle = true
hideAndroidData = false
hideModuleInjections = true
zygiskAutoScan = true
hideRecovery = true
cleanupLeftovers = true
inotifyWatcher = false
selinuxEnforce = false
nonStandardSdcardPathsHiding = true
nonStandardSdcardAndroidPathsHiding = true
unameSpoofing = true
avcLogSpoofing = true

[guard]
enabled = true
bootTimeout = 120
markerThreshold = 3
zygoteWatchSecs = 30
systemuiAbsentTimeout = 30
protectedModules = ["rezygisk", "zygisk_lsposed"]

[perf]
enabled = true
boostKhz = 0
schedMigrationCostNs = 500000
schedMinGranularityNs = 3000000
schedWakeupGranularityNs = 500000
schedChildRunsFirst = true

[adb]
adbRoot = false
developerOptions = false
usbDebugging = false
TOML

    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
}

# Simple TOML value getter (no nested support, flat keys only)
config_get() {
    local section="$1"
    local key="$2"
    local default="${3:-}"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return
    fi

    local in_section=0
    local value=""

    while IFS= read -r line; do
        # Check for section header
        case "$line" in
            \[$section\])
                in_section=1
                continue
                ;;
            \[*\])
                if [ $in_section -eq 1 ]; then
                    in_section=0
                fi
                continue
                ;;
        esac

        if [ $in_section -eq 1 ]; then
            # Strip comments and whitespace
            line=$(echo "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$line" ] && continue

            # Match key = value
            local k v
            k=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
            v=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')

            if [ "$k" = "$key" ]; then
                # Strip quotes from string values
                value=$(echo "$v" | sed 's/^"//' | sed 's/"$//' | sed "s/^'//" | sed "s/'$//")
                echo "$value"
                return
            fi
        fi
    done < "$CONFIG_FILE"

    echo "$default"
}

# Simple TOML value setter (creates key if missing)
config_set() {
    local section="$1"
    local key="$2"
    local value="$3"

    if [ ! -f "$CONFIG_FILE" ]; then
        init_config
    fi

    # Check if key exists
    local current
    current=$(config_get "$section" "$key")

    if [ -n "$current" ] || grep -q "^\[$section\]" "$CONFIG_FILE"; then
        # Update existing key
        local tmp_file="$CONFIG_FILE.tmp"
        local in_section=0
        local found=0

        > "$tmp_file"

        while IFS= read -r line; do
            case "$line" in
                \[$section\])
                    in_section=1
                    echo "$line" >> "$tmp_file"
                    continue
                    ;;
                \[*\])
                    if [ $in_section -eq 1 ]; then
                        in_section=0
                    fi
                    ;;
            esac

            if [ $in_section -eq 1 ] && [ $found -eq 0 ]; then
                local k
                k=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
                if [ "$k" = "$key" ]; then
                    echo "$key = $value" >> "$tmp_file"
                    found=1
                    continue
                fi
            fi

            echo "$line" >> "$tmp_file"
        done < "$CONFIG_FILE"

        # If key wasn't found, append to section
        if [ $found -eq 0 ]; then
            # Find section and append key after it
            local before after
            before=$(sed -n "1,/\[$section\]/p" "$CONFIG_FILE")
            after=$(sed "1,/\[$section\]/d" "$CONFIG_FILE")
            echo "$before" > "$tmp_file"
            echo "$key = $value" >> "$tmp_file"
            echo "$after" >> "$tmp_file"
        fi

        mv "$tmp_file" "$CONFIG_FILE"
    else
        # Add new section and key
        echo "" >> "$CONFIG_FILE"
        echo "[$section]" >> "$CONFIG_FILE"
        echo "$key = $value" >> "$CONFIG_FILE"
    fi

    chmod 600 "$CONFIG_FILE"
}

# Detect mount source
detect_mount_source() {
    if [ -n "$KSU" ] && [ "$KSU" = true ]; then
        echo "KSU"
    elif [ -n "$APATCH" ] && [ "$APATCH" = true ]; then
        echo "APatch"
    elif [ -d "/data/adb/magisk" ]; then
        echo "Magisk"
    else
        echo "Unknown"
    fi
}

# Sync device properties to config
sync_device_props() {
    local dev_lang=$(getprop ro.system.locale 2>/dev/null || getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null || echo "en")
    config_set "ui" "language" "$dev_lang"

    local dev_brand=$(getprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]')
    config_set "device" "brand" "$dev_brand"

    local vbmeta_size=$(( 4096 + ($(od -An -tu1 -N1 /dev/urandom 2>/dev/null || echo 0) % 8) * 1024 ))
    config_set "brene" "vbmeta_size" "$vbmeta_size"
}

# Sync TOML config to BRENE-style shell config
sync_brene_config() {
    local BRENE_FILE="$CONFIG_DIR/config_brene.sh"
    mkdir -p "$CONFIG_DIR"

    cat > "$BRENE_FILE" << 'BRENECONF'
# Auto-generated from config.toml - DO NOT EDIT MANUALLY
BRENECONF

    # Read each TOML value and map to BRENE variable
    local val

    val=$(config_get "brene" "nonStandardSdcardPathsHiding" "false")
    echo "config_paths_hiding__non_standard_sdcard=$([ "$val" = "true" ] && echo 1 || echo 0)" >> "$BRENE_FILE"

    val=$(config_get "brene" "nonStandardSdcardAndroidPathsHiding" "false")
    echo "config_paths_hiding__non_standard_sdcard_android=$([ "$val" = "true" ] && echo 1 || echo 0)" >> "$BRENE_FILE"

    val=$(config_get "brene" "hideAndroidData" "false")
    echo "config_paths_hiding__data_local_tmp=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    val=$(config_get "brene" "hideAndroidData" "false")
    echo "config_paths_hiding__sdcard_android_data_media_obb=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    val=$(config_get "brene" "selinuxEnforce" "false")
    echo "config_selinux=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_su_compat=1" >> "$BRENE_FILE"

    val=$(config_get "brene" "unameSpoofing" "false")
    echo "config_spoof_uname=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_selinux_hide=1" >> "$BRENE_FILE"
    echo "config_kernel_umount=1" >> "$BRENE_FILE"

    val=$(config_get "brene" "hideModuleInjections" "false")
    echo "config_hide_injections=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_hide_suspicious_pty=1" >> "$BRENE_FILE"

    val=$(config_get "brene" "hideRecovery" "false")
    echo "config_hide_custom_recovery=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    val=$(config_get "brene" "avcLogSpoofing" "false")
    echo "config_enable_avc_log_spoofing=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    val=$(config_get "brene" "hideSusMounts" "false")
    echo "config_umount_suspicious_mounts=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_hide_sus_mnts_for_non_su_procs=1" >> "$BRENE_FILE"
    echo "config_fix_data_local_tmp_inconsistencies=1" >> "$BRENE_FILE"

    val=$(config_get "brene" "propSpoofing" "false")
    echo "config_spoof_system_properties=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_spoof_system_properties_repeat=0" >> "$BRENE_FILE"

    val=$(config_get "brene" "spoofCmdline" "false")
    echo "config_spoof_cmdline_or_bootconfig=$([ "$val" = "true" ] && echo 1 || echo 1)" >> "$BRENE_FILE"

    echo "config_hide_addon_d=0" >> "$BRENE_FILE"
    echo "config_enable_log=0" >> "$BRENE_FILE"
    echo "config_pif_props=0" >> "$BRENE_FILE"
    echo "config_rom_props=0" >> "$BRENE_FILE"
    echo "config_saturation=0" >> "$BRENE_FILE"
    echo "config_brene_logs=0" >> "$BRENE_FILE"
    echo "config_usb_debugging=0" >> "$BRENE_FILE"
    echo "config_developer_options=0" >> "$BRENE_FILE"
    echo "config_custom_spoof_uname=0" >> "$BRENE_FILE"
    echo "config_wireless_debugging=0" >> "$BRENE_FILE"
    echo "config_hide_lineage_strings=0" >> "$BRENE_FILE"
    echo "config_spoof_libstagefright=0" >> "$BRENE_FILE"
    echo "config_hide_custom_rom_paths=0" >> "$BRENE_FILE"
    echo "config_hide_framework_res_apk=0" >> "$BRENE_FILE"

    val=$(config_get "brene" "verifiedBootHash" "")
    echo "config_spoof_verified_boot_hash='$val'" >> "$BRENE_FILE"
    echo "config_custom_uname_kernel_release='default'" >> "$BRENE_FILE"
    echo "config_custom_uname_kernel_version='default'" >> "$BRENE_FILE"

    chmod 600 "$BRENE_FILE"
}

# Main
case "$1" in
    init)
        init_config
        sync_device_props
        sync_brene_config
        echo "Config initialized"
        ;;
    get)
        config_get "$2" "$3" "${4:-}"
        ;;
    set)
        config_set "$2" "$3" "$4"
        echo "Config set: $2.$3 = $4"
        ;;
    dump)
        if [ -f "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "Config file not found"
            exit 1
        fi
        ;;
    source)
        detect_mount_source
        ;;
    *)
        echo "Usage: $0 {init|get|set|dump|source} [args...]"
        exit 1
        ;;
esac
