# 新建第二分区 128MB 从 303106 扇区开始
sudo fdisk /dev/sdc
n
p
2
303106
+262144
w

# 格式化文件系统为 ext4
sudo mkfs.ext4 /dev/sdc2

# 装载并复制文件系统
sudo mount /dev/sdc2 /mnt/rootfs/
sudo cp ./output/images/rootfs.tar /mnt/rootfs/
sudo tar -vxf /mnt/rootfs/rootfs.tar -C /mnt/rootfs
sudo rm /mnt/rootfs/rootfs.tar
sudo umount /mnt/rootfs