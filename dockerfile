FROM ubuntu:22.04
# RUN sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
#     sed -i s@/security.ubuntu.com/@/mirrors.ustc.edu.cn/@g /etc/apt/sources.list && \
#     sed -i s@/ports.ubuntu.com/@/mirrors.ustc.edu.cn/@g /etc/apt/sources.list  && \
#     echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup && \
#     echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache && \
#     echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/no-lang
RUN	apt update && \
apt -y install wget bzip2 xz-utils lib32z1 cmake vim 

RUN wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2
RUN tar xvf u-boot-2024.01.tar.bz2
RUN rm -r u-boot-2024.01.tar.bz2


# Linaro 7.5 已从 releases.linaro.org 下架，改用 ARM 官方 10.3 (兼容 H616)
RUN wget --no-check-certificate https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
RUN tar -xJvf gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
RUN mv gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
RUN ln -sf /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/*  /usr/bin/

RUN apt-get install -y bison libncurses-dev flex

RUN apt-get update && apt-get install -y python3 pip swig  git bc libusb-1.0-0-dev pkg-config

# ARM Trusted Firmware (bl31)
RUN git clone https://github.com/ARM-software/arm-trusted-firmware.git
RUN cd arm-trusted-firmware && make CROSS_COMPILE=aarch64-none-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31

# sunxi-tools
RUN git clone https://github.com/linux-sunxi/sunxi-tools
RUN apt-get install -y libfdt-dev
RUN cd /sunxi-tools && make

RUN apt-get install -y libssl-dev usbutils rsync

# U-Boot
COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c arch/arm/mach-sunxi/dram_sun50i_h616.c
RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig -j2
RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j2

# ====== apritzel linux h616-v13 内核（含 H616 HDMI DTS + 驱动） ======
RUN git clone -b h616-v13 https://github.com/apritzel/linux
RUN git config --global http.postBuffer 524288000

# 下载无线网卡驱动（让下面一步全缓存）
RUN git clone https://github.com/lwfinger/rtl8723ds
RUN git clone https://github.com/YuzukiHD/Xradio-XR829.git -b 5.15

# 复制无线驱动到 apritzel 内核树
RUN cp -r /rtl8723ds  /linux/drivers/net/wireless/realtek/rtl8723ds
RUN cp -r /Xradio-XR829  /linux/drivers/net/wireless/realtek/xr829
COPY ./rtl8Kconfig /linux/drivers/net/wireless/realtek/rtl8723ds/Kconfig
COPY ./realtek_Kconfig /linux/drivers/net/wireless/realtek/Kconfig
COPY ./linux_main_realtek_Makefile /linux/drivers/net/wireless/realtek/Makefile

# 复制项目自定义 DTS（含 ST7789 SPI 面板）
# 注意：apritzel h616-v13 的 sun50i-h616.dtsi 已有 HDMI/de/tcon/hdmi_phy 节点
#       自定义 DTS 需要引用这些标签来启用 HDMI
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts

# 用自定义 .config 编译 apritzel 内核（含 HDMI + WiFi 驱动）
COPY ./linux_main_menuconfig /linux/.config
RUN apt-get install -y libelf-dev apt-utils

RUN cd linux/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 Image
RUN cd linux/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 dtbs
RUN cd linux/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 modules

# 安装模块
RUN cd linux/ && mkdir -p MINSTALL HINSTALL
RUN cd linux/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL modules modules_install
RUN cd linux/ && make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# 生成 boot.scr
COPY ./boot.cmd /linux/boot.cmd
RUN apt install -y u-boot-tools
RUN cd /linux && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

# ====== Buildroot ======
RUN wget https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz
RUN tar -xvf buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
RUN apt install -y file cpio unzip
RUN cd /buildroot-2022.02.5 && make -j2

# Buildroot 第二遍（最终配置含更多包）
COPY ./buildroot_finally_config /buildroot-2022.02.5/.config
RUN cd /buildroot-2022.02.5 && make -j2

# 安装 SD 卡制作工具
RUN apt-get install -y kmod dosfstools fdisk

# ====== entrypoint ======
COPY ./entrypoint.sh /
COPY ./sdcard_make/shuaxie.sh /
RUN chmod a+x ./entrypoint.sh
RUN chmod a+x ./shuaxie.sh

# ====== Debian rootfs（需要 docker --privileged + binfmt_misc） ======
RUN apt-get install -y debootstrap qemu-user-static debian-archive-keyring
RUN mkdir -p /path/to/rootfs
RUN debootstrap --foreign --arch=arm64 bullseye /path/to/rootfs https://mirrors.tuna.tsinghua.edu.cn/debian/
RUN cp /usr/bin/qemu-aarch64-static /path/to/rootfs/usr/bin/
# 第二阶段在 chroot 内执行，需要在有 binfmt_misc 的 privileged 容器中运行
# 如果失败（缺少 binfmt），只打 warning，不影响 Buildroot 镜像
RUN chroot /path/to/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "/debootstrap/debootstrap --second-stage" || echo "WARNING: debootstrap second-stage failed (need binfmt_misc), skipping Debian rootfs"

# ====== 产物整理到 /out ======
RUN mkdir -p /out/buildroot /out/debian

# 内核产物
RUN cp /linux/arch/arm64/boot/Image /out/
RUN cp /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/
RUN cp /linux/boot.scr /out/
RUN cp -r /linux/MINSTALL/lib /out/modules
RUN cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/

# Buildroot rootfs
RUN cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/
RUN cp /buildroot-2022.02.5/output/images/rootfs.tar /out/buildroot/

# Debian rootfs（如果 debootstrap 成功）
RUN if [ -f /path/to/rootfs/etc/debian_version ]; then cp -a /path/to/rootfs/. /out/debian/; fi

# ====== 产物已就绪，SD 镜像请用 mksdimg.sh 在宿主机创建 ======
