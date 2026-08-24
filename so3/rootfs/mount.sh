#!/bin/bash
#
# Loop-mount rootfs.fat at fs/ so the deploy can copy the applications into
# it.
#
# Failing quietly here is what turns a transient problem into a boot image
# that is broken for good: the deploy carries on, rsync writes into a plain
# directory instead of the image, the FIT packs the untouched rootfs.fat, and
# the fault only surfaces at boot as
#
#     [SO3 ERROR] <fat_mount:340> Error 13 while mounting volume
#
# followed by a panic in the initial process. Error 13 is FatFs'
# FR_NO_FILESYSTEM. So: check everything, and say what to do about it.
#
# Copyright (c) 2026 REDS Institute - HEIG-VD

set -euo pipefail

echo "-------------------mount ramfs ---------------"

mkdir -p fs

if [ ! -f rootfs.fat ]; then
	printf "mount.sh: rootfs.fat is missing — create it with 'build.sh -x rootfs-so3'\n" >&2
	exit 1
fi

DEVLOOP=$(sudo losetup --partscan --find --show ./rootfs.fat)

if [ -z "${DEVLOOP}" ]; then
	printf "mount.sh: losetup gave no loop device for rootfs.fat\n" >&2
	exit 1
fi

# --partscan only creates <loop>p1 when the image really carries a partition
# table and a filesystem. No p1 means the image is blank.

if [ ! -b "${DEVLOOP}p1" ]; then
	printf "mount.sh: %sp1 does not exist — rootfs.fat carries no partition.\n" "${DEVLOOP}" >&2
	printf "          Recreate the image with 'build.sh -x rootfs-so3', then deploy again.\n" >&2
	sudo losetup -d "${DEVLOOP}"
	exit 1
fi

sudo mount "${DEVLOOP}p1" fs
