#! /bin/bash
rm -r /out/*
cd /buildroot-2022.02.5 && mkdir -p /out/rootfs && cp -r ./output/images/rootfs.tar /out/rootfs/
mkdir -p /out/uboot && cp -r /u-boot-2024.01/u-boot-sunxi-with-spl.bin  /out/uboot/

mkdir -p /out/image && cp -r /linux-6.0.19/arch/arm64/boot/Image /out/image/
mkdir -p /out/dtb/ && cp /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/

mkdir -p /out/bootscr && cp /linux-6.0.19/boot.scr /out/bootscr/
