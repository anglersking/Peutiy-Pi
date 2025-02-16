#!/bin/bash
DISK="./sdcard.img"
# 创建 images 目录
# mkdir images
# cd images

# # 收集需要用到的文件到 file 目录
# mkdir file 
# cp ../u-boot/u-boot-sunxi-with-spl.bin ./file
# cp ../linux-5.19.0/arch/arm64/boot/Image ./file
# cp ../linux-5.19.0/arch/arm64/boot/dts/allwinner/mq-quad.dtb ./file  // 这里我已经单独做了个设备树文件
# cp ../buildroot-2022.02.5/output/images/rootfs.tar ./file

# 制作空的 img 文件
sudo dd if=/dev/zero of=./sdcard.img bs=1M count=2048


fdisk $DISK << EOF
d   # 删除分区
d   # 删除分区，继续执行直到所有分区都被删除
d   # 如果有多个分区，重复执行删除

n   # 新建分区
p   # 主分区
1   # 分区号 1
40960  # 起始扇区（空出20MB用于uboot）
303104 # 结束扇区，设置分区大小为128MB

w   # 保存并退出
EOF

echo "分区创建完成"





sudo fdisk ./sdcard.img
n
p
1
40960
+131072 // 64MB

n
p
2
172033
1048575 // 默认

w
sudo losetup -f ./sdcard.img 

#查看关联到哪个位置
sudo losetup -l
/dev/loop11         0      0         0  0 /home/evler/Allwinner/MangoPi/Quad/mainline/images/sdcard.img

sudo dd if=./file/u-boot-sunxi-with-spl.bin of=/dev/loop11 bs=8K seek=1

# 参考分区：
设备          启动   起点    末尾   扇区  大小 Id 类型
./sdcard.img1       40960  172032 131073   64M 83 Linux
./sdcard.img2      172033 1048575 876543  428M 83 Linux

# -o （起始扇区 * 扇区大小）--sizelimit （扇区数量 * 扇区大小） 字节
sudo losetup -f -o 20971520 --sizelimit 67109376 sdcard.img 
sudo losetup -f -o 88080896 --sizelimit 448790016 sdcard.img 

#查看关联到哪个位置
sudo losetup -l
/dev/loop30  67109376 20971520         0  0 /home/evler/Allwinner/MangoPi/Quad/mainline/images/sdcard.img
/dev/loop26 448790016 88080896         0  0 /home/evler/Allwinner/MangoPi/Quad/mainline/images/sdcard.img

sudo mkfs.fat /dev/loop30
sudo mkfs.ext4 /dev/loop26

sudo mount /dev/loop30 /mnt/boot/
sudo mount /dev/loop26 /mnt/rootfs/

# 创建 boot.cmd 文件
vi boot.cmd

# 复制以下内容
setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw
setenv bootcmd fatload mmc 0:1 0x4fc00000 boot.scr; fatload mmc 0:1 0x40200000 Image; fatload mmc 0:1 0x4fa00000 mq-quad.dtb; booti 0x40200000 - 0x4fa00000

# 生成 boot.scr 文件
mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

sudo cp ./file/Image /mnt/boot/
sudo cp ./file/mq-quad.dtb /mnt/boot/
sudo cp ./file/boot.scr /mnt/boot/

# 解压 buildroot 制作出来的根文件系统压缩文件到 rootfs 分区
sudo tar -vxf ./file/rootfs.tar -C /mnt/rootfs/

# 安装内核模块到 rootfs 分区
cd ../linux-5.19.0/
sudo make INSTALL_MOD_PATH=/mnt/rootfs/ modules_install

sync
sudo umount /mnt/rootfs
sudo umount /mnt/boot

sudo losetup -d /dev/loop30
sudo losetup -d /dev/loop26
sudo losetup -d /dev/loop11

sudo dd if=./sdcard.img of=/dev/sdd