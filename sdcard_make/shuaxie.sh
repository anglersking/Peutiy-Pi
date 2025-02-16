#!/bin/bash
DISK="./sdcard.img"

loopmain="/dev/loop8"

loopboot="/dev/loop6"

loopnfs="/dev/loop7"

dd if=/out/uboot/u-boot-sunxi-with-spl.bin of=$loopmain bs=8K seek=1

sudo mkfs.fat $loopboot
sudo mkfs.ext4 $loopnfs
sudo mkdir -p /mnt/boot
sudo mkdir -p /mnt/rootfs
sudo mount  $loopboot /mnt/boot/
sudo mount  $loopnfs /mnt/rootfs/

sudo cp /out/image/Image /mnt/boot/
sudo cp /out/dtb/sun50i-h616-orangepi-zero2.dtb  /mnt/boot/
sudo cp /out/bootscr/boot.scr /mnt/boot/

# 解压 buildroot 制作出来的根文件系统压缩文件到 rootfs 分区
sudo tar -vxf /out/rootfs/rootfs.tar -C /mnt/rootfs/

cd /linux-6.0.19 && make INSTALL_MOD_PATH=/mnt/rootfs/ modules_install

sync
sudo umount /mnt/rootfs
sudo umount /mnt/boot

sudo losetup -d $loopmain
sudo losetup -d $loopboot
sudo losetup -d $loopnfs