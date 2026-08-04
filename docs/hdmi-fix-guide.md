# HDMI 显示修复指南

## 问题

Buildroot 镜像刷入 SD 卡后可以正常启动（串口可用），但 **HDMI 无显示**。

### 症状

```bash
ls /dev/fb*          # 无 framebuffer 设备
ls /sys/class/drm/   # 无 DRM 设备
dmesg | grep -i sun8i # 无 sun8i-dw-hdmi/sun8i-mixer 驱动加载日志
```

### 根因

Dockerfile 的编译流程存在**内核覆盖问题**，最终产出的内核并非来自含 HDMI 驱动的 `apritzel/linux` (`h616-v13`) 分支：

```dockerfile
# Step 1: 从 apritzel/linux (h616-v13) 克隆内核（含完整 H616 HDMI DTS + 驱动）
RUN git clone -b h616-v13 https://github.com/apritzel/linux

# Step 2: 第一次编译 apritzel 内核（含 HDMI）
RUN cd linux/ && make ... Image dtbs modules

# ❌ Step 3: clean 后重新 defconfig，再用主线 6.0.19 的 .config 覆盖
RUN cd linux/ && make ... clean
RUN cd linux/ && make ... defconfig          # ← 回退到默认配置
COPY ./linux_main_menuconfig /linux/.config  # ← 用主线 6.0.19 的配置覆盖！
RUN cd linux/ && make ... Image dtbs modules # ← 最终产物是主线配置+主线DTS

# ❌ Step 4: entrypoint.sh 拷贝的是 /linux-6.0.19/（旧目录名）
```

**结果：即使 apritzel 内核驱动已编译为模块，最终 entrypoint.sh 拷贝的是 `/linux-6.0.19/` 路径下的主线内核 Image + DTB，这个 DTB (`sun50i-h616-orangepi-zero2.dts`) 中没有 HDMI 节点。**

---

## 修复方案

### 修改 1: 修复 entrypoint.sh

`entrypoint.sh` 必须拷贝 `/linux/`（apritzel 内核）的产物，而不是旧的 `/linux-6.0.19/`：

```bash
#!/bin/bash
set -e

# === 这里之前是 /linux-6.0.19，需要改成 /linux === 

# Buildroot rootfs
mkdir -p /out/rootfs
cp -r /buildroot-2022.02.5/output/images/rootfs.tar /out/rootfs/ 2>/dev/null || true

# Buildroot ext2 rootfs
mkdir -p /out/buildroot
cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ 2>/dev/null || true
cp /buildroot-2022.02.5/output/images/rootfs.tar /out/buildroot/ 2>/dev/null || true

# U-Boot
mkdir -p /out/uboot
cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/uboot/

# Kernel Image → 从 /linux/ (apritzel 内核) 拷贝
mkdir -p /out/image
cp /linux/arch/arm64/boot/Image /out/image/

# DTB → 从 /linux/ (apritzel 内核) 拷贝（含 HDMI 节点）
mkdir -p /out/dtb
cp /linux/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/

# boot.scr
mkdir -p /out/bootscr
cp /linux/boot.scr /out/bootscr/

# 内核模块
mkdir -p /out/modules
cp -r /linux/MINSTALL/lib /out/modules/ 2>/dev/null || true

echo "=== All artifacts extracted ==="
```

### 修改 2: 修复 Dockerfile 的编译流程

用 `main_sun50i-h616-orangepi-zero2.dts`（仓库中已包含 SPI/ST7789 节点）替换 apritzel 内核的 DTS，避免 clean 后再 defconfig：

```dockerfile
# 1) 克隆 apritzel 内核（h616-v13 含 H616 HDMI DTS 节点和驱动）
RUN git clone -b h616-v13 https://github.com/apritzel/linux

# 2) 复制项目自定义 DTS（含 ST7789 SPI 面板 + 其他硬件描述）
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux/arch/arm64/boot/dts/allwinner/

# 3) 复制无线网卡驱动
RUN cp -r /rtl8723ds /linux/drivers/net/wireless/realtek/rtl8723ds
RUN cp -r /Xradio-XR829 /linux/drivers/net/wireless/realtek/xr829
COPY ./rtl8Kconfig /linux/drivers/net/wireless/realtek/rtl8723ds/Kconfig
COPY ./realtek_Kconfig /linux/drivers/net/wireless/realtek/Kconfig
COPY ./linux_main_realtek_Makefile /linux/drivers/net/wireless/realtek/Makefile

# 4) 编译 apritzel 内核（不要 clean 后 defconfig）
#    用自定义的 .config（已含 HDMI 驱动）
COPY ./linux_main_menuconfig /linux/.config
RUN cd /linux && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 Image
RUN cd /linux && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 dtbs
RUN cd /linux && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j2 modules

# 5) 安装模块
RUN cd /linux && mkdir -p MINSTALL HINSTALL
RUN cd /linux && make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- \
    INSTALL_MOD_PATH=./MINSTALL modules modules_install
RUN cd /linux && make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# 6) 生成 boot.scr
COPY ./boot.cmd /linux/boot.cmd
RUN cd /linux && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr
```

### 修改 3: 确保 DTS 有 HDMI 节点

`main_sun50i-h616-orangepi-zero2.dts` 当前缺少 HDMI 节点。需要添加：

```dts
// 在根节点下添加 HDMI 输出
&hdmi {
	hvcc-supply = <&reg_bldo1>;
	status = "okay";
};

&de {
	status = "okay";
};

&hdmi_phy {
	status = "okay";
};

&hdmi_out {
	hdmi_out_con: endpoint {
		remote-endpoint = <&hdmi_con_in>;
	};
};
```

> 注意：以上绑定名称来自 `apritzel/linux` h616-v13 分支的 `sun50i-h616.dtsi`，具体标签可能略有不同，编译时如报错需调整。

---

## 快速验证（镜像刷入后）

SD 卡启动后，在串口终端运行：

```bash
# HDMI 驱动是否加载
dmesg | grep -iE 'hdmi|sun8i-dw|mixer|tcon'

# DRM 设备是否存在
ls /sys/class/drm/

# framebuffer 是否创建
ls /dev/fb*
```

正常输出应有类似：
```
sun8i-dw-hdmi ... bound
sun8i-mixer ... bound
/dev/fb0
```

---

## 相关文件

| 文件 | 修改内容 |
|------|---------|
| `entrypoint.sh` | `/linux-6.0.19/` → `/linux/` |
| `dockerfile` | 移除第二次 clean+defconfig 编译（或确保最终产物来自 apritzel 内核） |
| `main_sun50i-h616-orangepi-zero2.dts` | 添加 HDMI/de/tcon 节点 |
| `linux_main_menuconfig` | 确认 `CONFIG_DRM_SUN8I_DW_HDMI=y`, `CONFIG_DRM_SUN8I_MIXER=y` 等已开启 |

---

*生成时间: 2026-08-05*
