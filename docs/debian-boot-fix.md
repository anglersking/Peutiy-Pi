# Peutiy-Pi Debian 镜像启动修复指南

## 问题

`v1.0-alpha` Release 中的 `sdcard_debian.img` 无法正常启动。内核加载 rootfs 后找不到 init 进程，直接 kernel panic：

```
Run /sbin/init as init process
Kernel panic - not syncing: Requested init /sbin/init failed (error -2)
```

### 根因

通过 `debugfs` 检查 rootfs 分区（分区 2，ext4），发现：

- **`/sbin/init` 不存在**（没有文件，也不是符号链接）
- **`/lib/systemd/systemd` 也不存在**（systemd 二进制缺失）
- `/lib/systemd/system/` 目录下只有 service/timer 文件，但 systemd 自身没装进去

换句话说，rootfs 里安装了 systemd 的 unit/service 文件，但没有安装 systemd 这个包本身。

### 为什么会这样

很可能是构建流程中 `debootstrap` 第二阶段或 `chroot` 安装 systemd 的步骤出了问题。常见原因：

1. **debootstrap 第二阶段未完成** — 第一阶段只下载了基础包，第二阶段（`--second-stage`）需要在目标架构的 chroot 中运行，如果没有 QEMU 用户态模拟（`qemu-aarch64-static`）或没有在板子上跑第二阶段，systemd 就不会被正确配置
2. **chroot 安装 systemd 失败** — `apt install systemd` 时依赖没拉全，或者 `dpkg --configure -a` 没跑完
3. **手动清理过头** — 构建脚本可能删除了某些文件时误把 systemd 二进制也干掉了

---

## 修复方案

### 方案 A：手动修复现有镜像（推荐新手）

在 x86 机器上挂载镜像的 rootfs 分区，手动安装 systemd：

```bash
# 1. 创建 loop 设备挂载分区 2（offset = 303105 × 512 = 155189760）
OFFSET=$((303105*512))
sudo mount -o loop,offset=$OFFSET sdcard_debian.img /mnt/rootfs

# 2. 挂载虚拟文件系统
sudo mount --bind /dev  /mnt/rootfs/dev
sudo mount --bind /proc /mnt/rootfs/proc
sudo mount --bind /sys  /mnt/rootfs/sys

# 3. 复制 QEMU 用户态模拟器（非 ARM 机器需要）
# macOS: brew install qemu，然后：
sudo cp "$(brew --prefix)/bin/qemu-aarch64-static" /mnt/rootfs/usr/bin/
# Linux: apt install qemu-user-static，然后：
# sudo cp /usr/bin/qemu-aarch64-static /mnt/rootfs/usr/bin/

# 4. chroot 进去重新安装 systemd
sudo chroot /mnt/rootfs /bin/bash

# === 以下命令在 chroot 内执行 ===
apt update
apt install --reinstall systemd
# 验证 /sbin/init 存在（应该是 → /lib/systemd/systemd 的符号链接）
ls -la /sbin/init
# 如果符号链接没自动创建，手动创建：
ln -sf /lib/systemd/systemd /sbin/init
exit
# === chroot 结束 ===

# 5. 卸载
sudo umount /mnt/rootfs/dev
sudo umount /mnt/rootfs/proc
sudo umount /mnt/rootfs/sys
sudo umount /mnt/rootfs

# 6. 检查一下 /sbin/init 是否真的存在于镜像中
OFFSET=$((303105*512))
debugfs -R "ls -l /sbin/init" "sdcard_debian.img?offset=$OFFSET"
```

> 前提：安装 `qemu`（macOS: `brew install qemu`；Linux: `apt install qemu-user-static`）

### 方案 B：修复构建脚本（根本修复）

在 `create_debian_rootfs.sh` 中确保以下几点：

#### 1. 确保第二阶段在 ARM64 环境下执行

```bash
# debootstrap 分两步：第一阶段在任意架构下载包，第二阶段必须在目标架构执行

# ❌ 错误做法
debootstrap --foreign --arch=arm64 buster /rootfs
# 然后直接在 x86 机器上 chroot（会失败！）

# ✅ 正确做法
debootstrap --foreign --arch=arm64 buster /rootfs

# 复制 QEMU 模拟器
cp /usr/bin/qemu-aarch64-static /rootfs/usr/bin/

# 用 QEMU 模拟 ARM 环境执行第二阶段
chroot /rootfs /debootstrap/debootstrap --second-stage
```

#### 2. 第二阶段完成后验证关键文件

```bash
# 验证 systemd 是否安装成功
chroot /rootfs ls -la /sbin/init
# 应该输出: /sbin/init -> /lib/systemd/systemd (或类似路径)

chroot /rootfs ls -la /lib/systemd/systemd
# 应该存在二进制文件

# 如果不存在，在 chroot 内修复
chroot /rootfs apt update
chroot /rootfs apt install --reinstall systemd
```

#### 3. 如果是 multistrap 方式构建

确认 multistrap 配置的 `packages` 字段里包含 `systemd`：

```
packages=... systemd systemd-sysv ...
```

并且构建完成后验证：

```bash
ls -la /rootfs/sbin/init    # 必须存在
ls -la /rootfs/lib/systemd/systemd  # 必须存在
```

#### 4. 打包前最终检查

```bash
# 在 chroot 内逐项检查
chroot /rootfs /bin/bash -c "
  which systemd        # 确认 systemd 二进制可执行
  systemctl --version  # 确认 systemd 能正常输出版本
  ls -la /sbin/init    # 确认 init 符号链接存在
  dpkg -l systemd      # 确认 systemd 包状态为 ii（已安装）
"
```

---

## 验证清单（打包镜像前）

| 检查项 | 命令 | 期望结果 |
|--------|------|---------|
| `/sbin/init` 存在 | `ls -la /rootfs/sbin/init` | 符号链接 → `/lib/systemd/systemd` |
| systemd 二进制存在 | `file /rootfs/lib/systemd/systemd` | ELF 64-bit ARM aarch64 |
| systemd 可执行 | `chroot /rootfs systemctl --version` | 输出版本号 |
| dpkg 包状态 | `chroot /rootfs dpkg -l systemd` | `ii` 开头（已安装） |

---

## 附件

- 镜像分区布局:
  - 分区 1: FAT32 (boot)，startsector=40960，262145 sectors
  - 分区 2: ext4 (rootfs)，startsector=303105，745471 sectors
  - rootfs mount offset: `303105 × 512 = 155189760`

---

*生成时间: 2026-08-04*
