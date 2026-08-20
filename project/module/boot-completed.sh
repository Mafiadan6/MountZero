#!/bin/bash
# MountZero VFS - Boot Completed Script
# Runs after boot_completed

MODDIR=${0%/*}
PATH=/data/adb/ksu/bin:$PATH
KSU_BIN=/data/adb/ksud
SUSFS_BIN=/data/adb/ksu/bin/susfs
PERSISTENT_DIR=/data/adb/mountzero

# KernelSU features
${KSU_BIN} feature set su_compat 1 2>/dev/null
${KSU_BIN} feature set kernel_umount 1 2>/dev/null
${KSU_BIN} feature set selinux_hide 1 2>/dev/null
${KSU_BIN} feature save 2>/dev/null

# SELinux enforcing
[ "$(getenforce 2>/dev/null)" != "Enforcing" ] && setenforce 1 2>/dev/null

# Update module description
susfs_ver=$(${SUSFS_BIN} show version 2>/dev/null)
description="MountZero VFS - VFS path redirection + root hiding"
if [ -n "${susfs_ver}" ]; then
    ${KSU_BIN} module config set override.description "[Status: OK | SUSFS: ${susfs_ver}] ${description}" 2>/dev/null
else
    ${KSU_BIN} module config set override.description "[Status: SUSFS missing] ${description}" 2>/dev/null
fi

echo "mountzero: boot-completed.sh done" > /dev/kmsg 2>/dev/null
