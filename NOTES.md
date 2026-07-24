# 嵌入式 Linux 开发笔记

> H616 (Orange Pi Zero2) 主线 Linux + Buildroot 开发过程记录

---

## 内核配置

### =m vs =y

- `=y`：编译进内核本体（Image），开机就有，不用管
- `=m`：编成 .ko 模块文件，放在 /lib/modules/，需要手动 modprobe 加载
- 原则：显示驱动、基础驱动用 `=y`；WiFi 等可选外设可以用 `=m`

### modprobe

加载内核模块的命令：

```bash
modprobe 8723ds          # 加载模块
modprobe -v 8723ds       # -v 显示详细信息
lsmod                     # 查看已加载的模块
rmmod 8723ds              # 卸载模块
```

---

## 设备树 (Device Tree)

### 是什么

告诉内核这块板子上有什么硬件、接在哪个引脚。内核是通用的，设备树是"硬件清单"。

```
.dts (源文件) → 编译 → .dtb (二进制) → U-Boot 传给内核 → 内核初始化硬件
```

### 常见操作

```dts
// 启用外设（DTSI 里默认 disabled 的必须写）
&hdmi {
    status = "okay";
};

// 启用 SPI + 挂设备
&spi1 {
    status = "okay";
    pinctrl-0 = <&spi1_pins>, <&spi1_cs0_pin>;

    display@0 {
        compatible = "sitronix,st7789v";
        reg = <0>;
        spi-max-frequency = <32000000>;
        dc-gpios = <&pio 6 6 GPIO_ACTIVE_HIGH>;
        reset-gpios = <&pio 6 7 GPIO_ACTIVE_LOW>;
    };
};

// GPIO LED
led {
    gpios = <&pio 2 15 GPIO_ACTIVE_HIGH>;
    default-state = "on";
};

// I2C 传感器（引脚在总线节点指定，设备只写地址）
&i2c3 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&i2c3_pa_pins>;   // PA10=SCL, PA11=SDA  ← 引脚在这里

    mpu6050@68 {
        compatible = "invensense,mpu6050";
        reg = <0x68>;               // I2C 从设备地址，不是引脚
        interrupt-parent = <&pio>;
        interrupts = <0 12 IRQ_TYPE_EDGE_RISING>;  // 中断脚（可选）
    };
};
```

---

## 添加外设的通用流程

```
① 硬件接线 → ② 写设备树 → ③ 开内核 CONFIG → ④ 编译 → ⑤ 应用层使用
```

### 外设引脚指定方式

| 外设类型 | 在哪指定引脚 | 例子 |
|----------|-------------|------|
| I2C | `pinctrl-0` 在总线节点 | `&i2c3 { pinctrl-0 = <&i2c3_pa_pins>; }` |
| SPI | `pinctrl-0` 在总线节点 | `&spi1 { pinctrl-0 = <&spi1_pins>, <&spi1_cs0_pin>; }` |
| GPIO（DC/RESET等） | `xxx-gpios` 在设备节点 | `dc-gpios = <&pio 6 6 GPIO_ACTIVE_HIGH>;` |
| 中断 | `interrupts` 在设备节点 | `interrupts = <0 12 IRQ_TYPE_EDGE_RISING>;` |

**为什么 I2C/SPI 引脚在总线层？** 因为 SCL/SDA 或 CLK/MOSI/MISO 是总线上所有设备共享的，设备节点只写自己的地址（`reg`）。

### 判断要不要写 C 驱动

```bash
# 在内核源码里搜 compatible 字符串
grep -rn "芯片型号" linux-6.0.19/drivers/

# 搜到了 → 有现成驱动，只写 DTS
# 搜不到 → 需要自己写 C
```

大多数外设（LED、按键、I2C 传感器、SPI 屏、WiFi）内核已有驱动，**只写设备树就够了**。

### 需要写 C 的情况

- 小众/自研芯片
- FPGA 自定义协议
- 非标通信时序
- 需要内核态做复杂计算

---

## 写一个简单的 GPIO LED 驱动

### 驱动代码 (myled.c)

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/gpio.h>

static int led_gpio = 15;  // 根据实际接线改

static int __init myled_init(void)
{
    int ret;
    ret = gpio_request(led_gpio, "my_led");
    if (ret) return ret;
    ret = gpio_direction_output(led_gpio, 1);  // 默认亮
    if (ret) { gpio_free(led_gpio); return ret; }
    pr_info("myled: initialized on GPIO %d\n", led_gpio);
    return 0;
}

static void __exit myled_exit(void)
{
    gpio_set_value(led_gpio, 0);
    gpio_free(led_gpio);
}

module_init(myled_init);
module_exit(myled_exit);
MODULE_LICENSE("GPL");
```

### Makefile

```makefile
obj-m += myled.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
```

### 交叉编译

```bash
make -C linux-6.0.19 M=$(pwd) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules
```

---

## 驱动的三种用户接口

| 方式 | 路径 | 操作 | 适用 |
|------|------|------|------|
| sysfs | `/sys/class/xxx/attr` | `echo 1 > attr` | 简单开关，脚本控制 |
| device file | `/dev/xxx` | `open/write` | 经典方式 |
| ioctl | `/dev/xxx` | `ioctl(fd, cmd, arg)` | 复杂命令、传结构体 |

### sysfs 实现（最常用）

```c
#include <linux/sysfs.h>

static ssize_t led_store(struct class *cls, struct class_attribute *attr,
                         const char *buf, size_t count)
{
    int val;
    kstrtoint(buf, 10, &val);
    gpio_set_value(led_gpio, val ? 1 : 0);
    return count;
}

static ssize_t led_show(struct class *cls, struct class_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", gpio_get_value(led_gpio));
}

static struct class_attribute led_attr = __ATTR(led, 0660, led_show, led_store);

// init 里加：
led_class = class_create(THIS_MODULE, "myled");
class_create_file(led_class, &led_attr);
```

### 为什么 echo 1 就能亮灯

```
用户空间                    内核空间
─────────────────────────────────────
echo 1 > /sys/class/myled/led
    │
    ▼
write() 系统调用
    │
    ▼
sysfs → __ATTR 绑定的 led_store()
    │
    ▼
kstrtoint("1") → 1
    │
    ▼
gpio_set_value(led_gpio, 1)
    │
    ▼
GPIO 输出高电平 → LED 亮
```

**`__ATTR(name, mode, show, store)` 就是把文件名和函数绑定起来的宏。**

---

## H616 HDMI 显示流水线

```
display-engine (de) → hdmi 控制器 → hdmi_out 端口 → hdmi-connector → 物理 HDMI
    mixer0                DW HDMI          endpoint       Type D Micro
```

关键：`sun50i-h616.dtsi` 里 de/hdmi 默认 `status = "disabled"`，必须在自己的 DTS 里显式 `status = "okay"`。

---

## 常用调试命令

```bash
# 查看 framebuffer
cat /proc/fb
ls /sys/class/graphics/

# 查看 DRM
ls /sys/class/drm/
cat /sys/class/drm/card0-HDMI-A-1/status    # HDMI 连接状态
cat /sys/class/drm/card0-HDMI-A-1/modes     # 支持的分辨率

# 切换 framebuffer console
con2fbmap 1 0   # tty1 → fb0 (HDMI)
con2fbmap 1 1   # tty1 → fb1 (ST7789)

# GPIO
cat /sys/kernel/debug/gpio                   # 查看所有 GPIO 状态

# I2C
i2cdetect -y 0                               # 扫描 I2C0 总线上的设备

# 内核日志
dmesg | tail -50
dmesg | grep -i drm
dmesg | grep -i spi

# 模块
lsmod                                        # 已加载模块
modprobe xxx                                 # 加载模块
modinfo xxx.ko                               # 查看模块信息
```
