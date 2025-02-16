# 在buildroot中执行 替换根文件系统
sudo mount /dev/sdd2 /mnt/rootfs
sudo rm -rf /mnt/rootfs/*
sudo cp output/images/rootfs.tar /mnt/rootfs/
sudo tar -xvf /mnt/rootfs/rootfs.tar -C /mnt/rootfs/

# 在内核中执行 安装模块到第二分区的rootfs中（因为内核没经过裁剪会有大量的模块安装到第二分区，可能需要调整下第二分区的大小）
make INSTALL_MOD_PATH=/mnt/rootfs/ modules modules_install

# 卸载rootfs
sync
sudo umount /mnt/rootfs/