
# This Makefile helps the build of the SO3 environment for SYE labs

.PHONY: so3 usr compile deploy clean

all:	compile deploy
	echo "Compilation done"

compile: usr so3
	@set -e
	echo "Compilation done"

deploy:
	@set -e
	echo "Deploying..."
	./deploy.sh -br
	

init:
	@set -e
	cd filesystem && ./create_img.sh vexpress
	cd rootfs && ./create_ramfs.sh virt32 && ./deploy.sh virt32

so3:
	@set -e
	cd so3 && make virt32_defconfig && make

usr:
	@echo Compiling usr and deploying in the root filesystem ...
	@set -e
	cd usr && ./build.sh

boot:
	@echo Compiling bootloader with virt32_config
	@set -e
	cd u-boot && make virt32_defconfig && make

clean:
	cd so3 && make clean
	cd usr && rm -rf build
