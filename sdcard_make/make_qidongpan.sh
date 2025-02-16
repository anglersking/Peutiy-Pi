# 进入磁盘管理
fdisk /dev/sdd

# 多执行几次删除所有分区
d

# 新建分区 （扇区为单位，前面空开20MB用于存放uboot，制作128MB的分区）
n
p
40960
303104
w

# 进行 FAT 格式化
sudo mkfs.fat /dev/sdd1

# 写入 uboot 到 8KB 的位置
sudo dd if=./u-boot/u-boot-sunxi-with-spl.bin of=/dev/sdd bs=8K seek=1

# 挂载 FAT 文件系统
sudo mount /dev/sdd1 /mnt/boot/

# 复制内核以及设备树到FAT分区
sudo cp linux-6.0-rc3/arch/arm64/boot/Image /mnt/boot/
sudo cp linux-6.0-rc3/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /mnt/boot/

# 卸载 FAT 文件系统
sudo umount /mnt/boot