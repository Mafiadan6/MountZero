#!/bin/bash
#
# MountZero Integration Script
# Run from your kernel source root directory
# Usage: ./project/integrate.sh [--patch]
#
# Without --patch: copies files directly (for already-patched kernels)
# With --patch:    applies the kernel patch via git apply
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$(pwd)"
MZ_KERNEL="$SCRIPT_DIR/kernel"
PATCH_DIR="$MZ_KERNEL/patches"

echo "========================================"
echo "  MountZero VFS Integration"
echo "========================================"

# Check running from kernel source
if [ ! -d "$KERNEL_DIR/fs" ]; then
    echo "❌ Run this from YOUR KERNEL SOURCE ROOT!"
    echo "   Not from the MountZero project folder."
    exit 1
fi

# Detect kernel version for patch selection
KVER=$(make kernelversion 2>/dev/null)
if [ -z "$KVER" ]; then
    echo "⚠️  Cannot detect kernel version, assuming 4.14"
    KVER="4.14.0"
fi
KMAJOR=$(echo "$KVER" | cut -d. -f1)
KMINOR=$(echo "$KVER" | cut -d. -f2)
PATCH_NAME="mountzero_${KMAJOR}.${KMINOR}_kernel_integration.patch"

echo "  Kernel version: $KVER"

# Check for SUSFS
if [ -f "$KERNEL_DIR/include/linux/susfs_def.h" ] || \
   grep -q "CONFIG_KSU_SUSFS" "$KERNEL_DIR"/*/defconfig 2>/dev/null || \
   grep -q "CONFIG_KSU_SUSFS" "$KERNEL_DIR"/arch/*/configs/* 2>/dev/null; then
    echo "  ✅ SUSFS found"
else
    echo "  ⚠️  WARNING: SUSFS not detected (CONFIG_KSU_SUSFS=y required)"
fi

if [ "$1" = "--patch" ]; then
    echo ""
    echo "🔧 Applying patch: $PATCH_NAME"
    
    PATCH_FILE="$PATCH_DIR/$PATCH_NAME"
    if [ ! -f "$PATCH_FILE" ]; then
        echo "❌ Patch not found: $PATCH_FILE"
        echo "   Available patches:"
        ls "$PATCH_DIR/" 2>/dev/null
        exit 1
    fi
    
    # Check if already patched
    if grep -q "CONFIG_MOUNTZERO" "$KERNEL_DIR/fs/Kconfig" 2>/dev/null; then
        echo "  ⏭️  Already patched (CONFIG_MOUNTZERO found in Kconfig)"
    else
        git apply --check "$PATCH_FILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            git apply "$PATCH_FILE"
            echo "  ✅ Patch applied successfully"
        else
            echo "⚠️  git apply failed, trying with --reject..."
            git apply --reject "$PATCH_FILE" 2>&1
            echo "  ⚠️  Check for .rej files if there were conflicts"
        fi
    fi
else
    echo ""
    echo "📁 Copying kernel files..."
    
    # Check MountZero files exist
    if [ ! -f "$MZ_KERNEL/mountzero.c" ]; then
        echo "❌ MountZero kernel files not found!"
        exit 1
    fi
    
    cp -v "$MZ_KERNEL/mountzero.c" "$KERNEL_DIR/fs/"
    cp -v "$MZ_KERNEL/mountzero.h" "$KERNEL_DIR/include/linux/"
    
    # Add to Makefile
    if ! grep -q "mountzero.o" "$KERNEL_DIR/fs/Makefile" 2>/dev/null; then
        echo "" >> "$KERNEL_DIR/fs/Makefile"
        echo "obj-y += mountzero.o" >> "$KERNEL_DIR/fs/Makefile"
        echo "  ✅ Added to fs/Makefile"
    fi
    
    # Add to Kconfig
    if [ -f "$KERNEL_DIR/fs/Kconfig" ]; then
        if ! grep -q "config MOUNTZERO" "$KERNEL_DIR/fs/Kconfig" 2>/dev/null; then
            echo "" >> "$KERNEL_DIR/fs/Kconfig"
            echo "config MOUNTZERO" >> "$KERNEL_DIR/fs/Kconfig"
            echo -e "\tbool \"MountZero VFS Path Redirection\"" >> "$KERNEL_DIR/fs/Kconfig"
            echo -e "\tdefault y" >> "$KERNEL_DIR/fs/Kconfig"
            echo -e "\thelp" >> "$KERNEL_DIR/fs/Kconfig"
            echo -e "\t  VFS path redirection, directory hiding," >> "$KERNEL_DIR/fs/Kconfig"
            echo -e "\t  and mmap spoofing for systemless modules." >> "$KERNEL_DIR/fs/Kconfig"
            echo "  ✅ Added to fs/Kconfig"
        fi
    fi
    
    echo ""
    echo "⚠️  Manual: Add hooks to namei.c, dcache.c, readdir.c,"
    echo "   stat.c, statfs.c, proc/task_mmu.c"
    echo "   (See kernel/patches/ for exact hook points)"
fi

echo ""
echo "========================================"
echo "  Next steps:"
echo "========================================"
echo ""
echo "  1. Add to defconfig:  CONFIG_MOUNTZERO=y"
echo "  2. Build:             make -j\$(nproc)"
echo "  3. Flash boot.img + install module.zip"
echo ""
echo "========================================"
echo "✅ Done!"
echo "========================================"
