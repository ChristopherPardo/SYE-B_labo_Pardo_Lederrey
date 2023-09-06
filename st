

N_QEMU_INSTANCES=`ps -A | grep qemu | wc -l`
GDB_PORT_BASE=1234


QEMU_MAC_ADDR=`printf 'DE:AD:BE:EF:%02X:%02X\n' $(($RANDOM % 255)) $((N_QEMU_INSTANCES))`
QEMU_GDB_PORT=$(($GDB_PORT_BASE + $N_QEMU_INSTANCES))


echo -e 'MAC:\t\t' $QEMU_MAC_ADDR
echo -e 'GDB Port:\t' $QEMU_GDB_PORT '\n\n'


 sudo qemu-system-arm $@ \
    -gdb tcp::$QEMU_GDB_PORT \
	-smp 2 \
	-serial mon:stdio  \
	-M virt  -cpu cortex-a15 \
	-device virtio-blk-device,drive=hd0 \
	-drive if=none,file=filesystem/sdcard.img,id=hd0,format=raw,file.locking=off \
	-m 1024 \
	-bios u-boot/u-boot.bin \
	-net tap,script=scripts/qemu-ifup.sh,downscript=scripts/qemu-ifdown.sh -net nic,macaddr=${QEMU_MAC_ADDR} \
	-nographic 
 
