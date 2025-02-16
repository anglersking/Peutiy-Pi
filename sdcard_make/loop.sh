#!/bin/bash
DISK="./sdcard.img"
sudo dd if=/dev/zero of= $DISK bs=1M count=2048
losetup -f $DISK
losetup -f -o 352323584  --sizelimit 4294966272  $DISK
losetup -f -o 20971520 --sizelimit 67109376  $DISK
losetup -l |grep $DISK

