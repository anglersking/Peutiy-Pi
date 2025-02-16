setenv bootargs 'console=ttyS0,115200'
setenv bootcmd 'fatload mmc 0:1 0x40200000 Image;fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb;booti 0x40200000 - 0x4fa00000'
setenv bootargs 'console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw  init=/sbin/init debug panic=30'
saveenv