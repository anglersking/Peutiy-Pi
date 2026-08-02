#!/bin/sh
# Peutiy-Pi SD 镜像制作脚本
# 在宿主机 (iStoreOS) 运行, 前提: docker build 已完成, 产物在 OUTDIR

set -e

OUTDIR="${1:-/mnt/nvme0n1-4/out}"
SIZE_MB="${2:-512}"

cd "$OUTDIR" || { echo "ERROR: $OUTDIR not found"; exit 1; }

# 宿主机上可能缺 mkfs.fat, 先检查
MKFS_FAT=$(command -v mkfs.fat || command -v mkfs.vfat || echo "")
if [ -z "$MKFS_FAT" ]; then
    echo "ERROR: mkfs.fat not found, try: opkg install dosfstools"
    exit 1
fi

make_img() {
    local NAME="$1"
    local ROOTFS_SRC="$2"
    local ROOTFS_TYPE="$3"  # "tar" or "cp"

    echo "=== Creating ${NAME} (${SIZE_MB}M) ==="
    rm -f "$NAME"

    dd if=/dev/zero of="$NAME" bs=1M count=$SIZE_MB

    # 创建双分区: p1=FAT(boot 128M), p2=Linux(rootfs 剩余)
    # 扇区: 40960=20MB偏移(留uboot), 303104=20M+128M=148MB
    fdisk "$NAME" << EOF
n
p
1
40960
303104
n
p
2
303105

w
EOF

    LOOP=$(losetup -f)
    losetup -P $LOOP "$NAME"

    $MKFS_FAT -F 32 ${LOOP}p1
    mkfs.ext4 -F ${LOOP}p2

    # 写入 U-Boot 到 8KB 偏移
    dd if=u-boot-sunxi-with-spl.bin of=$LOOP bs=8K seek=1

    # 写入 boot 分区
    MNT=$(mktemp -d)
    mount ${LOOP}p1 $MNT
    cp Image "$MNT/"
    cp sun50i-h616-orangepi-zero2.dtb "$MNT/"
    cp boot.scr "$MNT/"
    umount $MNT

    # 写入 rootfs 分区
    MNT2=$(mktemp -d)
    mount ${LOOP}p2 $MNT2
    if [ "$ROOTFS_TYPE" = "tar" ]; then
        tar xf "$ROOTFS_SRC" -C "$MNT2"
    else
        cp -a "$ROOTFS_SRC/." "$MNT2/"
    fi
    cp -r modules "$MNT2/lib/"
    umount $MNT2

    losetup -d $LOOP
    rm -rf $MNT $MNT2
    echo "=== ${NAME} OK ==="
}

# --- Buildroot SD 镜像 ---
make_img sdcard_buildroot.img buildroot/rootfs.tar tar

# --- Debian SD 镜像 ---
if [ -f debian/etc/debian_version ]; then
    make_img sdcard_debian.img debian cp
else
    echo "=== Skipping sdcard_debian.img (no debian rootfs) ==="
fi

echo ""
echo "=== DONE ==="
ls -lh sdcard_*.img
