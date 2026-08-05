FROM ubuntu:22.04

# ====== 一次性安装所有 apt 包（减少 layer） ======
RUN apt update && \
    apt -y install \
        wget bzip2 xz-utils lib32z1 cmake vim \
        bison libncurses-dev flex \
        python3 pip swig git bc libusb-1.0-0-dev pkg-config \
        libfdt-dev libssl-dev usbutils rsync \
        file cpio unzip u-boot-tools \
        libelf-dev apt-utils kmod dosfstools fdisk \
        debootstrap qemu-user-static debian-archive-keyring || \
    true

# ====== U-Boot ======
RUN wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2 && \
    tar xvf u-boot-2024.01.tar.bz2 && \
    rm u-boot-2024.01.tar.bz2

# ====== ARM 10.3 交叉编译器 ======
RUN wget --no-check-certificate https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz && \
    tar -xJf gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz && \
    mv gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu && \
    ln -sf /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/* /usr/bin/ && \
    rm gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz

# ====== ARM Trusted Firmware (bl31) ======
RUN git clone https://github.com/ARM-software/arm-trusted-firmware.git && \
    cd arm-trusted-firmware && make CROSS_COMPILE=aarch64-none-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31

# ====== sunxi-tools ======
RUN git clone https://github.com/linux-sunxi/sunxi-tools && \
    cd /sunxi-tools && make

# ====== 编译 U-Boot ======
COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c arch/arm/mach-sunxi/dram_sun50i_h616.c
RUN cd u-boot-2024.01 && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig -j2 && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j2
# 注意: 上面两条 make 不是重复 —— 第一条是 defconfig, 第二条才编译

# ====== apritzel linux h616-v13 内核（含 HDMI DTS + 驱动） ======
RUN git config --global http.postBuffer 524288000 && \
    git clone -b h616-v13 https://github.com/apritzel/linux && \
    git clone https://github.com/lwfinger/rtl8723ds && \
    git clone https://github.com/YuzukiHD/Xradio-XR829.git -b 5.15


# 修复 rtl8723ds 在 5.19 内核上的 API 不兼容
# stop_ap: 5.19 没有 link_id 参数(6.0 才加); wdev->connected 在 5.19 已移除
RUN sed -i "s/KERNEL_VERSION(5, 19, 0)/KERNEL_VERSION(6, 0, 0)/g" \
        /rtl8723ds/os_dep/linux/ioctl_cfg80211.c

# 无线驱动拷入内核树
RUN cp -r /rtl8723ds /linux/drivers/net/wireless/realtek/rtl8723ds && \
    cp -r /Xradio-XR829 /linux/drivers/net/wireless/realtek/xr829
COPY ./rtl8Kconfig /linux/drivers/net/wireless/realtek/rtl8723ds/Kconfig
COPY ./realtek_Kconfig /linux/drivers/net/wireless/realtek/Kconfig
COPY ./linux_main_realtek_Makefile /linux/drivers/net/wireless/realtek/Makefile

# 使用 YuzukiHD dtsi (包含 HDMI display pipeline: mixer/tcon/hdmi)
COPY ./sun50i-h616-yuzuki.dtsi /linux/arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi

# 自定义 DTS + 内核配置
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts
COPY ./linux_main_menuconfig /linux/.config

# 编译内核（一次到位，不 clean）
RUN cd linux/ && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 Image && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 dtbs && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 modules && \
    mkdir -p MINSTALL HINSTALL && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL modules_install && \
    make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# boot.scr
COPY ./boot.cmd /linux/boot.cmd
RUN cd /linux && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

# ====== Buildroot ======
RUN wget https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz && \
    tar -xvf buildroot-2022.02.5.tar.gz && \
    rm buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
RUN cd /buildroot-2022.02.5 && make -j2

# Buildroot 第二遍（最终配置）
COPY ./buildroot_finally_config /buildroot-2022.02.5/.config
RUN cd /buildroot-2022.02.5 && make -j2

# ====== Debian rootfs ======
RUN mkdir -p /path/to/rootfs && \
    debootstrap --foreign --arch=arm64 bullseye /path/to/rootfs https://mirrors.tuna.tsinghua.edu.cn/debian/ && \
    cp /usr/bin/qemu-aarch64-static /path/to/rootfs/usr/bin/ && \
    chroot /path/to/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "/debootstrap/debootstrap --second-stage" || \
    echo "WARNING: debootstrap second-stage failed (need binfmt_misc), skipping Debian rootfs"

# ====== 产物整理到 /out ======
RUN mkdir -p /out/buildroot /out/debian && \
    cp /linux/arch/arm64/boot/Image /out/ && \
    cp /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/ && \
    cp /linux/boot.scr /out/ && \
    cp -r /linux/MINSTALL/lib /out/modules && \
    cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.tar /out/buildroot/ && \
    if [ -f /path/to/rootfs/etc/debian_version ]; then cp -a /path/to/rootfs/. /out/debian/; fi

# ====== 入口脚本 ======
COPY ./entrypoint.sh /entrypoint.sh
COPY ./sdcard_make/shuaxie.sh /shuaxie.sh
RUN chmod a+x /entrypoint.sh /shuaxie.sh
