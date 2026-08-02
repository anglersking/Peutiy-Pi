# Peutiy-Pi (菩提派)

基于全志 H616 的自制 Linux 开发板，从零构建主线 Linux 系统。
基于 Buildroot + 主线 U-Boot + apritzel h616-v13 内核，完全脱离芯片厂 BSP。

## 硬件

- **SoC**: 全志 H616 (Quad-core Cortex-A53 @ 1.5GHz)
- **开发板**: Peutiy-Pi（菩提派），兼容 Orange Pi Zero2 设计
- **PCB**: 自制六层板
- **电源管理**: AXP305
- **存储**: MicroSD + SPI NOR Flash
- **网络**: 千兆以太网 + WiFi (RTL8723DS / XR829)

### 显示输出

| 接口 | 状态 | 说明 |
|------|------|------|
| HDMI | ✅ 支持 | DRM 框架，最大 4K@30Hz，apritzel h616-v13 内核原生驱动 |
| ST7789 1.47" LCD | ✅ 支持 | SPI1 接口，172×320，可用于无显示器时应急操作 |

**HDMI 和 ST7789 双显共存**：系统启动后两个显示设备同时注册 (`/dev/fb0` 和 `/dev/fb1`)，可通过 `con2fbmap` 在运行时切换 console 输出：

```bash
# 切换到 ST7789
con2fbmap 1 1

# 切回 HDMI
con2fbmap 1 0

# 查看显示状态
cat /sys/class/drm/card0-HDMI-A-1/status
```

### ST7789 接线 (Orange Pi Zero2 40pin 排针)

| ST7789 | 排针号 | GPIO |
|--------|--------|------|
| GND | 6/20/25 等 | GND |
| VCC | 1/17 | 3.3V |
| SCL | 29 | PH6 (SPI1_CLK) |
| SDA | 31 | PH7 (SPI1_MOSI) |
| RES (MISO) | 33 | PH8 (SPI1_MISO) |
| CS | 27 | PH5 (SPI1_CS0) |
| DC | 22 | PG6 |
| RST | 16 | PG7 |
| BL | 3.3V 或 GPIO | 背光，可直接接 3.3V |

![实体板子](./picture/4.jpg)
![PCB布线](./picture/5.png)

## 构建环境

本项目使用 Docker 构建，隔离环境依赖。

### 构建组件

| 组件 | 版本 | 说明 |
|------|------|------|
| ARM Trusted Firmware | mainline master | BL31 |
| U-Boot | 2024.01 | Bootloader, orangepi_zero2_defconfig |
| Linux Kernel | h616-v13 (apritzel) | 含 HDMI/H616 完整驱动 + 无线网卡驱动 |
| GCC 工具链 | ARM 10.3 (aarch64-none-linux-gnu) | 替代已下架的 Linaro 7.5 |
| Buildroot | 2022.02.5 | 根文件系统 + 编译无线驱动后重编内核 |
| Debian | Bullseye arm64 | debootstrap 引导，备选 rootfs |

## 快速开始

### 方式一：一键构建 + 出 SD 镜像（推荐）

```bash
git clone https://github.com/anglersking/Peutiy-Pi.git
cd Peutiy-Pi

# 一条命令：编译 + 提取产物 + 制作 SD img
# 产物自动输出到 /mnt/nvme0n1-4/out/
sh build_all.sh /mnt/nvme0n1-4/out
```

### 方式二：只编译（产物在容器内）

```bash
docker build --network=host -t h616_core_build . 2>&1 | tee build.log
# 产物在容器 /out/ 下，需要手动 docker cp 出来
```

### 提取构建产物 (方式二后续)

```bash
# 创建 out 目录并运行容器
mkdir -p out
docker run --rm --privileged \
  -v $(pwd)/out:/out \
  h616_core_build \
  /bin/sh -c "cp -r /out/. /mnt_out/"

# 或者直接从 container 拷出
docker cp $(docker create h616_core_build):/out ./
```

### 3. 产物说明

```
out/
├── Image                                   # Linux 内核镜像
├── sun50i-h616-orangepi-zero2.dtb           # 设备树二进制
├── boot.scr                                # U-Boot 启动脚本（设置 root=/dev/mmcblk0p2）
├── u-boot-sunxi-with-spl.bin                # U-Boot + SPL 镜像
├── modules/                                # 内核模块目录
├── buildroot/
│   ├── rootfs.ext2                         # Buildroot 根文件系统 (ext2)
│   └── rootfs.tar                          # Buildroot 根文件系统 (tar)
├── debian/                                 # Debian Buster arm64 rootfs
├── sdcard_buildroot.img                    # ✅ Buildroot 完整 SD 卡镜像 (512M, 双分区, 可直接刷)
└── sdcard_debian.img                       # ✅ Debian 完整 SD 卡镜像 (512M, 双分区, 可直接刷)
```

每个 `.img` 文件结构：

```
分区1 (FAT32, 128M):  /Image  /sun50i-h616-orangepi-zero2.dtb  /boot.scr
分区2 (ext4,  ~380M):  rootfs + /lib/modules/
8KB 偏移:              U-Boot SPL
```

### 4. 直接刷入 SD 卡

```bash
# ⚠️ 请确认设备！/dev/sdX 是你的 SD 卡
# 用 lsblk 确认你的 SD 卡设备名

# 刷 Buildroot 版本：
dd if=out/sdcard_buildroot.img of=/dev/sdX bs=4M status=progress

# 刷 Debian 版本：
dd if=out/sdcard_debian.img of=/dev/sdX bs=4M status=progress
```

刷完后插卡到 Orange Pi Zero2 上电即可启动。

### 5. 手动制作 SD 卡（如果想自己分步操作）

```bash
export sdcard=sdc  # ⚠️ 改成你的 SD 卡设备名，不要写错！

# 1. 清空分区表
dd if=/dev/zero of=/dev/$sdcard bs=1M count=10

# 2. 创建双分区 (预留 20MB 给 U-Boot)
fdisk /dev/$sdcard << EOF
n
p
1

+128M
n
p
2


w
EOF

# 3. 写入 U-Boot 到 8KB 偏移
dd if=out/u-boot-sunxi-with-spl.bin of=/dev/$sdcard bs=8K seek=1

# 4. 格式化
mkfs.fat /dev/${sdcard}1
mkfs.ext4 /dev/${sdcard}2

# 5. 写入 boot 分区
mount /dev/${sdcard}1 /mnt/boot/
cp out/Image /mnt/boot/
cp out/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
cp out/boot.scr /mnt/boot/
umount /mnt/boot

# 6. 写入 rootfs 分区

# Buildroot 版:
mount /dev/${sdcard}2 /mnt/rootfs/
tar xf out/buildroot/rootfs.tar -C /mnt/rootfs
cp -r out/modules /mnt/rootfs/lib/
umount /mnt/rootfs

# Debian 版:
mount /dev/${sdcard}2 /mnt/rootfs/
cp -a out/debian/. /mnt/rootfs/
cp -r out/modules /mnt/rootfs/lib/
umount /mnt/rootfs
```

## Boot 流程

```
BROM → SPL → ATF (BL31) → U-Boot → Linux Kernel → RootFS
```

U-Boot 启动参数 (`boot.cmd` → `boot.scr`)：

```
bootargs: console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init
bootcmd:  fatload mmc 0:1 0x40200000 Image
          fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
          booti 0x40200000 - 0x4fa00000
```

## 调试

```bash
# 串口: UART0 (PH0=TX, PH1=RX), 115200 8N1
screen /dev/ttyUSB0 115200

# HDMI 显示测试
cat /sys/class/drm/card0-HDMI-A-1/status  # 查看 HDMI 连接状态
cat /sys/class/drm/card0-HDMI-A-1/modes   # 查看支持的分辨率

# ST7789 显示测试
fbtest --fb /dev/fb1
```

## 项目结构

```
├── dockerfile                     # Docker 构建文件 (主要)
├── buildroot.config               # Buildroot 基础配置
├── buildroot_finally_config       # Buildroot 最终配置 (含无线驱动重编后)
├── linux_main_menuconfig          # Linux 内核 .config
├── linux_main_realtek_Makefile    # Realtek 驱动 Makefile
├── realtek_Kconfig                # Realtek 驱动 Kconfig
├── rtl8Kconfig                    # RTL8723DS Kconfig
├── main_sun50i-h616-orangepi-zero2.dts  # 设备树 overlay
├── boot.cmd                       # U-Boot 启动脚本源文件
├── uboot_config                   # U-Boot defconfig
├── uboot_config                   # U-Boot 配置
├── dram_sun50i_h616.c             # U-Boot DRAM 初始化
├── axp305.c                       # U-Boot AXP305 PMIC 驱动
├── entrypoint.sh                  # 容器入口脚本
├── build.sh                       # Docker 构建脚本
├── auto_write.sh                  # SD 卡自动烧录脚本
├── fixbug/                        # 驱动修复补丁
├── picture/                       # 项目图片
└── sdcard_make/                   # SD 卡制作脚本
```

## 注意事项

- **内核来源**: 使用 apritzel/linux `h616-v13` 分支，含完整 HDMI/H616 驱动 + DTS
- **不要用主线 linux-6.0.19** — 缺少 H616 HDMI DTS 节点 (`&de`/`&hdmi`/`&hdmi_out`)
- **工具链**: ARM 官方 10.3，前缀 `aarch64-none-linux-gnu-`
- **编译并行度**: `-j2` (适配路由器弱 CPU)，如果自己的机器跑可以改大
- **rootfs 大小**: Buildroot ext2 分区改为 256M (128M 不够放下 sshd 等组件)
- **Buildroot 构建源**: 已配置清华 tuna 镜像源加速国内下载
