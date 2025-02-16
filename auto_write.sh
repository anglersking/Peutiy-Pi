export sdcard=sdc
export num1=1
export num2=2


dd if=./out/uboot/u-boot-sunxi-with-spl.bin of=/dev/$sdcard bs=8K seek=1
mount /dev/$sdcard$num1 /mnt/boot/
sudo cp ./out/image/Image /mnt/boot/
sudo cp ./out/dtb/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
umount /mnt/boot

sudo mount /dev/$sdcard$num2 /mnt/rootfs/
sudo cp ./out/rootfs/rootfs.tar /mnt/rootfs/
sudo tar -vxf /mnt/rootfs/rootfs.tar -C /mnt/rootfs
sudo rm /mnt/rootfs/rootfs.tar
sudo umount /mnt/rootfs
