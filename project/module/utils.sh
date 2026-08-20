#!/bin/bash
# MountZero VFS - Utility Functions (BRENE-compatible)
PATH=/data/adb/ksu/bin:$PATH
MODDIR=${0%/*}
KSU_BIN=/data/adb/ksud
KSU_MODULES_DIR=/data/adb/modules
SUSFS_BIN=/data/adb/ksu/bin/susfs
PERSISTENT_DIR=/data/adb/mountzero

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
    resetprop -n "$1" "$2" 2>/dev/null
}

if_prop_value_exits_resetprop_n() {
    local PROP_NAME=$1
    local EXPECTED_VALUE=$2
    local CURRENT_VALUE
    CURRENT_VALUE=$(resetprop "$PROP_NAME" 2>/dev/null)
    [ -z "$CURRENT_VALUE" ] || [ "$CURRENT_VALUE" = "$EXPECTED_VALUE" ] && return
    resetprop -n "$PROP_NAME" "$EXPECTED_VALUE" 2>/dev/null
}

spoof_android_system_properties() {
    resetprop_n "init.svc.adbd" "stopped"
    resetprop_n "init.svc_debug_pid.adbd" ""
    resetprop_n "persist.sys.usb.config" "mtp"
    resetprop_n "ro.adb.secure" "1"
    resetprop_n "ro.crypto.state" "encrypted"
    resetprop_n "ro.debuggable" "0"
    resetprop_n "ro.force.debuggable" "0"
    resetprop_n "ro.kernel.qemu" ""
    resetprop_n "ro.secure" "1"
    resetprop_n "ro.build.selinux" "1"
    resetprop_n "ro.build.selinux.enforce" "1"
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
    resetprop_n "ro.boot.vbmeta.size" "4096"
    resetprop_n "ro.boot.vbmeta.hash_alg" "sha256"
    resetprop_n "ro.boot.vbmeta.avb_version" "1.3"
    resetprop_n "ro.boot.vbmeta.device_state" "locked"
    resetprop_n "ro.boot.vbmeta.invalidate_on_error" "yes"

    if_prop_value_exits_resetprop_n "ro.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.vendor.boot.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.vendor.warranty_bit" "0"
    if_prop_value_exits_resetprop_n "ro.boot.warranty_bit" "0"

    local fingerprint_value
    fingerprint_value=$(resetprop ro.build.fingerprint 2>/dev/null)
    if [ -n "$fingerprint_value" ]; then
        local new_fingerprint_value="${fingerprint_value//userdebug/user}"
        new_fingerprint_value="${new_fingerprint_value//evolution/}"
        new_fingerprint_value="${new_fingerprint_value//crdroid/}"
        new_fingerprint_value="${new_fingerprint_value//lineage/}"
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

    local new_utc_value
    new_utc_value=$(resetprop ro.build.date.utc 2>/dev/null)
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

    resetprop -d "ro.boot.verifiedbooterror" 2>/dev/null
    resetprop -d "ro.boot.verifyerrorpart" 2>/dev/null
    resetprop -d "crashrecovery.rescue_boot_count" 2>/dev/null
    resetprop -d service.adb.root 2>/dev/null
    resetprop -d service.adb.tcp.port 2>/dev/null
    resetprop -d "init.svc.magisk" 2>/dev/null
    resetprop -d "init.svc.magisk_patcher" 2>/dev/null

    local sdk
    sdk=$(resetprop ro.build.version.sdk 2>/dev/null)
    if [ -n "$sdk" ] && [ "$sdk" -ge 36 ] 2>/dev/null; then
        resetprop -d sys.oem_unlock_allowed 2>/dev/null
    else
        resetprop_n "sys.oem_unlock_allowed" "0"
    fi

    resetprop -c --force 2>/dev/null
}

brene_sus_path() {
    ${SUSFS_BIN} add_sus_path "$1" 2>/dev/null
}
brene_sus_path_loop() {
    ${SUSFS_BIN} add_sus_path_loop "$1" 2>/dev/null
}
brene_sus_map() {
    ${SUSFS_BIN} add_sus_map "$1" 2>/dev/null
}
brene_set_uname() {
    ${SUSFS_BIN} set_uname "$1" "$2" 2>/dev/null
}
brene_sus_mount() {
    ${KSU_BIN} kernel notify-module-mounted 2>/dev/null
    ${KSU_BIN} kernel umount add -f 2 "$1" 2>/dev/null
}
