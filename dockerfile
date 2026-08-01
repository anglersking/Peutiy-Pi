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
# COPY ./u-boot-2024.01.tar.bz2 /
RUN tar xvf u-boot-2024.01.tar.bz2
RUN rm -r u-boot-2024.01.tar.bz2


# Linaro 7.5 已从 releases.linaro.org 下架，改用 ARM 官方 10.3 (兼容 H616)
RUN wget --no-check-certificate https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
RUN tar -xJvf gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz
RUN mv gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
RUN ln -sf /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/*  /usr/bin/


RUN apt-get install -y bison libncurses-dev flex

# /usr/local/arm64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu$



RUN apt-get update && apt-get install -y python3 pip swig  git bc libusb-1.0-0-dev pkg-config

RUN git clone https://github.com/ARM-software/arm-trusted-firmware.git
# COPY ./arm-trusted-firmware /arm-trusted-firmware
RUN cd arm-trusted-firmware && make CROSS_COMPILE=aarch64-none-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31


RUN  git clone https://github.com/linux-sunxi/sunxi-tools
# COPY ./sunxi-tools /sunxi-tools
RUN apt-get install -y  libfdt-dev
RUN  cd /sunxi-tools && make

RUN apt-get install -y libssl-dev

RUN apt-get install -y usbutils rsync



COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c arch/arm/mach-sunxi/dram_sun50i_h616.c
RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig -j100

RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j100

RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.gz
# COPY ./linux-6.0.19.tar.gz /
RUN tar -xvf linux-6.0.19.tar.gz

RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 Image
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 dtbs
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 modules
#RUN  apt install -y depmod
RUN  cd linux-6.0.19/ && mkdir MINSTALL && mkdir HINSTALL
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
RUN  cd linux-6.0.19/ &&   make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install



RUN wget  https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz
RUN tar -xvf buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
RUN apt install -y file cpio unzip
RUN cd /buildroot-2022.02.5 && make -j100

RUN git config --global http.postBuffer 524288000

# RUN  git clone -b h616-v13 https://github.com/apritzel/linux
RUN   git clone https://github.com/lwfinger/rtl8723ds
RUN git clone https://github.com/YuzukiHD/Xradio-XR829.git -b 5.15
RUN echo "start downloads linux apritzel"

COPY ./boot.cmd /linux-6.0.19/boot.cmd
RUN apt install -y u-boot-tools
RUN cd /linux-6.0.19 && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr


# # COPY ./out/linux /linux
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- clean

RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
RUN cp -r /rtl8723ds  /linux-6.0.19/drivers/net/wireless/realtek/rtl8723ds
RUN cp -r /Xradio-XR829  /linux-6.0.19/drivers/net/wireless/realtek/xr829

COPY ./rtl8Kconfig /linux-6.0.19/drivers/net/wireless/realtek/rtl8723ds/Kconfig
# COPY ./xr89Kconfig /linux-6.0.19/drivers/net/wireless/realtek/xr829/Kconfig

COPY ./realtek_Kconfig /linux-6.0.19/drivers/net/wireless/realtek/Kconfig

# COPY ./realtek_Kconfig /linux/drivers/net/wireless/realtek/Kconfig
# COPY ./linux_main_realtek_Makefile /linux/drivers/net/wireless/realtek/Makefile
COPY ./linux_main_realtek_Makefile /linux-6.0.19/drivers/net/wireless/realtek/Makefile
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux-6.0.19/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts
# # # RUN make menuconfig
COPY ./linux_main_menuconfig /linux-6.0.19/.config

RUN apt-get install -y libelf-dev apt-utils
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 Image
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 dtbs
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 modules

RUN  cd linux-6.0.19/ && rm -r MINSTALL/*  && rm -r HINSTALL/*
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
RUN  cd linux-6.0.19/ &&   make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# COPY ./fixbug/ioctl_cfg80211.c /linux/drivers/net/wireless/realtek/rtl8723ds/os_dep/linux/ioctl_cfg80211.c
# RUN cd /linux &&  make modules -j100

COPY ./buildroot_finally_config /buildroot-2022.02.5/.config
# COPY ./fixbug/ioctl_cfg80211.c linux/drivers/net/wireless/realtek/rtl8723ds/os_dep/linux/ioctl_cfg80211.c
# RUN cd /linux &&  make modules -j100
RUN  cd /buildroot-2022.02.5 && make -j100
RUN apt-get install -y kmod dosfstools
COPY ./entrypoint.sh /
COPY ./sdcard_make/shuaxie.sh /
RUN chmod a+x ./entrypoint.sh
RUN chmod a+x ./shuaxie.sh

#debian
RUN apt-get install debootstrap qemu-user-static
RUN mkdir /path/to/rootfs
RUN debootstrap --foreign --arch=arm64 buster /path/to/rootfs https://deb.debian.org/debian
RUN cp /usr/bin/qemu-aarch64-static /path/to/rootfs/usr/bin/
RUN chroot /path/to/rootfs /debootstrap/debootstrap --second-stage
# RUN chroot /path/to/rootfs /bin/bash

# ENTRYPOINT ["/entrypoint.sh"]

# # 在内核中执行 安装模块到第二分区的rootfs中（因为内核没经过裁剪会有大量的模块安装到第二分区，可能需要调整下第二分区的大小）
# make INSTALL_MOD_PATH=/mnt/rootfs/ modules modules_install

#USB 启动UBOOT 
#../sunxi-tools/sunxi-fel uboot u-boot-sunxi-with-spl.bin


# sunxi-fel -v uboot u-boot-sunxi-with-spl.bin \
#              write 0x40200000 Image \
#              write 0x4fa00000 sun50i-a64-pine64-lts.dtb \
#              write 0x4fc00000 boot.scr \
#              write 0x4ff00000 rootfs.cpio.lzma.uboot

# # 例如：
# ./sunxi-tools/sunxi-fel -v uboot u-boot/u-boot-sunxi-with-spl.bin \
# write 0x40200000 linux-6.0-rc3/arch/arm64/boot/Image \
# write 0x4fa00000 linux-6.0-rc3/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb \ 
# write 0x4fc00000 boot.scr


#制作启动盘
# 进入磁盘管理
# fdisk /dev/sdd

# # 多执行几次删除所有分区
# d

# # 新建分区 （扇区为单位，前面空开20MB用于存放uboot，制作128MB的分区）
# n
# p
# 40960
# 303104
# w

# # 进行 FAT 格式化
# sudo mkfs.fat /dev/sdd1

# # 写入 uboot 到 8KB 的位置
# sudo dd if=./u-boot/u-boot-sunxi-with-spl.bin of=/dev/sdd bs=8K seek=1

# # 挂载 FAT 文件系统
# sudo mount /dev/sdd1 /mnt/boot/

# # 复制内核以及设备树到FAT分区
# sudo cp linux-6.0-rc3/arch/arm64/boot/Image /mnt/boot/
# sudo cp linux-6.0-rc3/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /mnt/boot/

# # 卸载 FAT 文件系统
# sudo umount /mnt/boot

#测试 TF 卡启动内核

# 手动装载内核以及设备树并启动
# fatload mmc 0:1 0x40200000 Image
# fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
# setenv bootargs 'console=ttyS0,115200 earlycon'
# booti 0x40200000 - 0x4fa00000

# # 使用如下设置变量并保存到FAT分区
# setenv bootargs 'console=ttyS0,115200'
# setenv bootcmd 'fatload mmc 0:1 0x40200000 Image;fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb;booti 0x40200000 - 0x4fa00000'
# saveenv

# # 使用 bootcmd 启动
# boot





# COPY ./main_sun50i-h616-orangepi-zero2.dts /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts
# RUN cd /linux && make dtbs

# RUN git clone https://github.com/apritzel/linux.git -b h616-v13

# RUN apt install -y dkmop
# RUN make -j100
# RUN git clone -b h616-v13 https://github.com/apritzel/linux
# RUN git clone https://github.com/lwfinger/rtl8723ds 
# RUN cp /rtl8723ds /linux/drivers/net/wireless/realtek/rtl8723ds

# 14  ls
#   115  cd linux-6.0.19/
#   116  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- defconfig
#   117  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 Image
#   118  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 dtbs
#   119  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j100 modules
#   120  ls
#   121  mkdir MINSTALL
#   122  mkdir HINSTALL
#   123  ake ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
#   124  make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
#   125  make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install
#   126  apt-get install rsync
#   127  make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install
#   128  sudo dd if=../u-boot-2024.01/u-boot-sunxi-with-spl.bin of=/dev/sdc bs=8K seek=1
#   129  dd if=../u-boot-2024.01/u-boot-sunxi-with-spl.bin of=/dev/sdc bs=8K seek=1
#   130  ls /dev
#   131  sudo /dev/sdd1 /mnt/boot/
#   132  mount /dev/sdd1 /mnt/boot/
#   133  cd /mnt/
#   134  ls
#   135  mkdir boot
#   136  cd /linux-6.0.19/
#   137  ls
#   138  mount /dev/sdd1 /mnt/boot/
#   139  mount /dev/sdc1 /mnt/boot/
#   140  cp ./arch/arm64/boot/Image /mnt/boot/
#   141  cp ./arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
#   142  umount /mnt/boot
#   143  history
# root@yu-Vostro-15-3562:/li


# RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.gz
# RUN git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git


# /opt/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/aarch64-linux-gnu/libc/usr/include/linux/version.h
# apt install file cpio  unzip
