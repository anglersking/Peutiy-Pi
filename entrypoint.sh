#! /bin/bash
set -e

# ====== Peutiy-Pi 产物提取脚本 ======
# 从 Docker 构建容器中提取内核/DTB/rootfs 到 /out 目录

rm -rf /out/*

# Buildroot rootfs
mkdir -p /out/rootfs
cp -r /buildroot-2022.02.5/output/images/rootfs.tar /out/rootfs/ 2>/dev/null || true

# Buildroot ext2 image
mkdir -p /out/buildroot
cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ 2>/dev/null || true

# Debian rootfs
mkdir -p /out/debian
if [ -d /path/to/rootfs ] && [ -f /path/to/rootfs/etc/debian_version ]; then
    cp -a /path/to/rootfs/. /out/debian/
fi

# U-Boot
mkdir -p /out/uboot
cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/uboot/

# Kernel Image (from apritzel/linux h616-v13)
mkdir -p /out/image
cp /linux/arch/arm64/boot/Image /out/image/

# DTB (from apritzel/linux h616-v13, includes HDMI nodes)
mkdir -p /out/dtb
cp /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/

# boot.scr
mkdir -p /out/bootscr
cp /linux/boot.scr /out/bootscr/

# Kernel modules
mkdir -p /out/modules
if [ -d /linux/MINSTALL/lib ]; then
    cp -r /linux/MINSTALL/lib /out/modules/
fi

echo "=== All artifacts extracted to /out ==="
ls -la /out/
