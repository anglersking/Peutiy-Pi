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

# ====== U-Boot ======
RUN wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2 && \
    tar xvf u-boot-2024.01.tar.bz2 && \
    rm u-boot-2024.01.tar.bz2

COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c /u-boot-2024.01/arch/arm/mach-sunxi/dram_sun50i_h616.c
RUN cd u-boot-2024.01 && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig -j2 && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j2

# ====== Linux 6.0.19 (主线内核，含完整 sunxi de33/hdmi 驱动) ======
RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.gz && \
    tar -xvf linux-6.0.19.tar.gz && \
    rm linux-6.0.19.tar.gz

# ====== Wi-Fi 驱动 ======
RUN git config --global http.postBuffer 524288000 && \
    git clone https://github.com/lwfinger/rtl8723ds && \
    git clone https://github.com/YuzukiHD/Xradio-XR829.git -b 5.15

# Note: rtl8723ds 在 6.0.19 上不需要 patch
# 6.0.19 > KERNEL_VERSION(5,19,0), stop_ap 有 link_id 参数, wdev->connected 存在

# 无线驱动拷入内核树
RUN cp -r /rtl8723ds /linux-6.0.19/drivers/net/wireless/realtek/rtl8723ds && \
    cp -r /Xradio-XR829 /linux-6.0.19/drivers/net/wireless/realtek/xr829

COPY ./rtl8Kconfig /linux-6.0.19/drivers/net/wireless/realtek/rtl8723ds/Kconfig
COPY ./realtek_Kconfig /linux-6.0.19/drivers/net/wireless/realtek/Kconfig
COPY ./linux_main_realtek_Makefile /linux-6.0.19/drivers/net/wireless/realtek/Makefile

# ====== YuzukiHD dtsi 覆盖（含完整 display engine pipeline: de33/mixer/TCON/HDMI/HDMI-PHY） ======
COPY ./sun50i-h616-yuzuki.dtsi /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi

# ====== 自定义 DTS（HDMI connector + ST7789 + Ethernet + WiFi + UART） ======
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts

# ====== 内核配置（已启用 sun4i DRM, DW HDMI, ST7789, rtl8723ds 等） ======
COPY ./linux_main_menuconfig /linux-6.0.19/.config

# ====== 编译内核 ======
RUN cd linux-6.0.19/ && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 Image && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 dtbs && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 modules && \
    mkdir -p MINSTALL HINSTALL && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL modules_install && \
    make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# ====== boot.scr ======
COPY ./boot.cmd /linux-6.0.19/boot.cmd
RUN cd /linux-6.0.19 && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

# ====== Buildroot ======
RUN wget https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz && \
    tar -xvf buildroot-2022.02.5.tar.gz && \
    rm buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
RUN cd /buildroot-2022.02.5 && make -j2

# Buildroot 第二遍（最终配置）
COPY ./buildroot_finally_config /buildroot-2022.02.5/.config
RUN cd /buildroot-2022.02.5 && make -j2

# ====== 把内核模块装进 Buildroot target ======
RUN mkdir -p /buildroot-2022.02.5/output/target/lib/modules && \
    cp -r /linux-6.0.19/MINSTALL/lib/modules/* /buildroot-2022.02.5/output/target/lib/modules/

# ====== Debian bullseye rootfs ======
RUN mkdir -p /path/to/rootfs && \
    debootstrap --foreign --arch=arm64 bullseye /path/to/rootfs https://mirrors.tuna.tsinghua.edu.cn/debian/ && \
    cp /usr/bin/qemu-aarch64-static /path/to/rootfs/usr/bin/ && \
    chroot /path/to/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "/debootstrap/debootstrap --second-stage" || \
    echo "WARNING: debootstrap second-stage failed (need binfmt_misc), skipping Debian rootfs"

# ====== 产物整理到 /out ======
RUN mkdir -p /out/buildroot /out/debian /out/image /out/dtb /out/uboot /out/modules /out/rootfs && \
    cp /linux-6.0.19/arch/arm64/boot/Image /out/image/ && \
    cp /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/ && \
    cp /linux-6.0.19/boot.scr /out/ && \
    cp -r /linux-6.0.19/MINSTALL/lib /out/modules/ && \
    cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/uboot/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.tar /out/rootfs/ && \
    if [ -f /path/to/rootfs/etc/debian_version ]; then cp -a /path/to/rootfs/. /out/debian/; fi

# ====== 入口脚本 ======
COPY ./entrypoint.sh /entrypoint.sh
COPY ./sdcard_make/shuaxie.sh /shuaxie.sh
RUN chmod a+x /entrypoint.sh /shuaxie.sh
