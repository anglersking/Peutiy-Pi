#! /bin/bash
set -e

# ====== Peutiy-Pi 产物提取脚本 ======
rm -rf /out/* 2>/dev/null || mkdir -p /out

# Kernel Image
mkdir -p /out/image
cp /linux-6.0.19/arch/arm64/boot/Image /out/image/

# DTB (含 HDMI + ST7789)
mkdir -p /out/dtb
cp /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/

# boot.scr
mkdir -p /out/bootscr
cp /linux-6.0.19/boot.scr /out/bootscr/

# Kernel modules
mkdir -p /out/modules
if [ -d /linux-6.0.19/MINSTALL/lib ]; then
    cp -r /linux-6.0.19/MINSTALL/lib /out/modules/
fi

# Buildroot rootfs
mkdir -p /out/buildroot
cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ 2>/dev/null || true
mkdir -p /out/rootfs
cp /buildroot-2022.02.5/output/images/rootfs.tar /out/rootfs/ 2>/dev/null || true

# Debian rootfs
mkdir -p /out/debian
if [ -d /path/to/rootfs ] && [ -f /path/to/rootfs/etc/debian_version ]; then
    cp -a /path/to/rootfs/. /out/debian/
fi

# U-Boot
mkdir -p /out/uboot
cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/uboot/ 2>/dev/null || true

echo "=== All artifacts extracted to /out ==="
ls -la /out/
