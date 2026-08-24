# Build environment for the SO3 Infrabase build system.
#
# The image carries ONLY the host environment: cross toolchains, host
# packages, Python. It contains NO project source.
#
# SYE is a virt32-only course (ARM 32-bit, QEMU virt, Cortex-A15), so
# this image is 32-bit only: the 64-bit Arm toolchains and the
# aarch64 MUSL toolchain are not built. Building a virt64/rpi4_64/
# verdin platform in this container will fail on a missing compiler,
# by design. The repository stays
# on the host and is bind-mounted by scripts/dbuild.sh at its own
# absolute path, so the same tree can be built from inside or outside
# the container interchangeably (bitbake stamps, the buildroot host tree,
# CMake caches and the *.attach.sha256 manifests all embed absolute paths).
#
# Build the image:  scripts/dbuild.sh --build
# Use it:           scripts/dbuild.sh build.sh bsp-so3
#                   scripts/dbuild.sh st.sh -d
#
# The build context is this directory only — never the project root,
# which holds tens of GB of build output.
#
# Copyright (c) 2026 REDS Institute - HEIG-VD

# ---------------------------------------------------------------------
# Stage 1 — build the MUSL cross toolchain for the SO3 user space
# ---------------------------------------------------------------------
#
# Without this, every fresh clone (or every wiped build/tmp) pays a
# ~15 min musl-cross-make build — binutils, gcc and musl compiled from
# source — before a single user application is built. Baking it into the
# image is the whole point of shipping a build container.
#
# This MUST stay in lockstep with the musl-toolchain recipe
# (build/meta-toolchain/recipes-toolchain/musl/musl-toolchain_1.0.bb):
# same musl-cross-make commit, same config.mak. The config.mak is not
# duplicated here — scripts/dbuild.sh copies the recipe's own file into
# the build context, so there is a single source of truth.

FROM ubuntu:24.04 AS musl

ENV DEBIAN_FRONTEND=noninteractive

# Pinned to SRCREV in musl-toolchain_1.0.bb.
ARG MUSL_CROSS_MAKE_REV=3635262e4524c991552789af6f36211a335a77b3

# IB_MUSL_TARGET:arm in local.conf. SYE is a virt32-only course, so the
# aarch64-linux-musl toolchain (virt64, rpi4_64, verdin) is deliberately
# NOT built — it would add ~270 MB for nothing. Add it back here if this
# tree ever needs a 64-bit platform:
#   docker build --build-arg MUSL_TARGETS="arm-linux-musleabihf aarch64-linux-musl" ...
ARG MUSL_TARGETS="arm-linux-musleabihf"

RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential git wget ca-certificates \
	patch tar xz-utils bzip2 gzip \
	m4 bison flex texinfo perl python3 \
	&& rm -rf /var/lib/apt/lists/*

COPY musl-config.mak /tmp/config.mak

RUN git clone https://github.com/richfelker/musl-cross-make /tmp/musl-cross-make \
	&& cd /tmp/musl-cross-make \
	&& git checkout --detach "${MUSL_CROSS_MAKE_REV}"

# One musl-cross-make run per target. OUTPUT mirrors the layout the
# recipe produces under build/tmp/toolchains, so the same
# <dir>/<target>/bin path works in both places.
RUN cd /tmp/musl-cross-make \
	&& for t in ${MUSL_TARGETS}; do \
		echo "=== building musl cross toolchain: $t ===" ; \
		cp /tmp/config.mak config.mak ; \
		echo "TARGET = $t" >> config.mak ; \
		echo "OUTPUT = /opt/toolchains/musl/$t" >> config.mak ; \
		make -j"$(nproc)" ; \
		make install ; \
		make clean ; \
	done \
	&& rm -rf /tmp/musl-cross-make /tmp/config.mak

# ---------------------------------------------------------------------
# Stage 2 — build the patched QEMU
# ---------------------------------------------------------------------
#
# The tree does not use the distribution's QEMU: meta-qemu patches the
# virt machine (0001-virt.c.patch, 0002-virt.h.patch) and configures it
# with a specific target and options. Compiling that from source is the
# longest single item of a first build, so it belongs in the image.
#
# This MUST stay in lockstep with meta-qemu: same tarball and sha256, same
# patches, same ./configure line. The patches are not duplicated here —
# scripts/dbuild.sh copies the recipe's own files into the build context,
# as it does for the musl config.mak.
#
# Installed under a prefix rather than left in its build tree, so QEMU
# finds its BIOS blobs and keymaps by itself.

FROM ubuntu:24.04 AS qemu

ENV DEBIAN_FRONTEND=noninteractive

# Pinned to the recipe (qemu_8.2.2.bb).
ARG QEMU_VERSION=8.2.2
ARG QEMU_SHA256=847346c1b82c1a54b2c38f6edbd85549edeb17430b7d4d3da12620e2962bc4f3

# SYE is virt32; QEMU_TARGET:virt32 in the recipe.
ARG QEMU_TARGET=arm-softmmu

# libfdt-dev matters: without a system libfdt, meson pulls the dtc
# subproject over git during configure — a network clone in the middle of
# an image build, and it fails outright when git is absent. git is kept
# anyway as a cheap safety net for any other wrap.

RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential python3 python3-venv ninja-build meson pkg-config \
	libglib2.0-dev libpixman-1-dev libsdl2-dev libslirp-dev libfdt-dev \
	git wget ca-certificates xz-utils patch \
	&& rm -rf /var/lib/apt/lists/*

COPY qemu-patches/ /tmp/qemu-patches/

RUN cd /tmp \
	&& wget -q "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" \
	&& echo "${QEMU_SHA256}  qemu-${QEMU_VERSION}.tar.xz" | sha256sum -c - \
	&& tar xf "qemu-${QEMU_VERSION}.tar.xz" \
	&& cd "qemu-${QEMU_VERSION}" \
	&& for p in /tmp/qemu-patches/*.patch; do \
		echo "applying $(basename "$p")" ; \
		patch -p1 < "$p" ; \
	done \
	&& ./configure --prefix=/opt/qemu --target-list="${QEMU_TARGET}" \
		--enable-slirp --disable-attr --disable-werror --disable-docs --enable-sdl \
	&& make -j"$(nproc)" \
	&& make install \
	&& cd /tmp && rm -rf "qemu-${QEMU_VERSION}" "qemu-${QEMU_VERSION}.tar.xz" /tmp/qemu-patches

# ---------------------------------------------------------------------
# Stage 3 — build U-Boot for virt32
# ---------------------------------------------------------------------
#
# U-Boot is not a host tool like the two above — it is part of the boot
# chain, built from 54 patches this repository owns. It is baked in for a
# different reason: so a student tree never has to carry its sources at
# all. Fetched, they are 190 MB that exist only to produce a 4.5 MB
# binary the course never modifies.
#
# The consequence is deliberate and worth stating: changing a U-Boot
# patch does NOT reach a container-built tree until this image is rebuilt.
# IB_UBOOT_PATH still prefers a U-Boot built in the tree, so anyone
# working on the boot chain runs `build.sh -x uboot` once and takes over.
#
# In lockstep with meta-uboot: same SRCREV, same patch series, same
# defconfig and CROSS_COMPILE. The patches come from the recipe via
# scripts/dbuild.sh, never duplicated here.

FROM ubuntu:24.04 AS uboot

ENV DEBIAN_FRONTEND=noninteractive

# Pinned to the recipe (uboot_2022.04.bb).
ARG UBOOT_SRCREV=e4b6ebd3de982ae7185dbf689a030e73fd06e0d2

# IB_PLATFORM / IB_TOOLCHAIN:arm for this course.
ARG UBOOT_DEFCONFIG=virt32_defconfig
ARG UBOOT_CROSS=arm-linux-gnueabihf-

RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential gcc-arm-linux-gnueabihf \
	bison flex libssl-dev bc swig python3 python3-dev python3-setuptools \
	git ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

COPY uboot-patches/ /tmp/uboot-patches/

# Fetch just the pinned commit rather than cloning master: the tree is
# large and only this revision is ever built.
RUN mkdir -p /tmp/u-boot && cd /tmp/u-boot \
	&& git init -q . \
	&& git remote add origin https://github.com/u-boot/u-boot \
	&& git fetch -q --depth 1 origin "${UBOOT_SRCREV}" \
	&& git checkout -q FETCH_HEAD \
	&& rm -rf .git

RUN cd /tmp/u-boot \
	&& for p in /tmp/uboot-patches/*.patch; do \
		echo "applying $(basename "$p")" ; \
		patch -p1 --batch --forward < "$p" ; \
	done \
	&& make CROSS_COMPILE="${UBOOT_CROSS}" "${UBOOT_DEFCONFIG}" \
	&& make CROSS_COMPILE="${UBOOT_CROSS}" -j"$(nproc)" \
	&& mkdir -p /opt/uboot \
	&& cp u-boot u-boot.bin /opt/uboot/ \
	&& cd /tmp && rm -rf u-boot uboot-patches

# ---------------------------------------------------------------------
# Stage 4 — the build environment proper
# ---------------------------------------------------------------------

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# BitBake requires a UTF-8 locale.

RUN apt-get update && apt-get install -y --no-install-recommends locales \
	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# OCI metadata. `source` is what attaches the package to a repository on
# GitHub Packages — it does NOT make it public, visibility is a separate
# and UI-only setting. This Dockerfile lives in the SYE course tree on
# reds-gitlab; the label points at the public SO3 repository whose build
# environment this is.

LABEL org.opencontainers.image.title="sye-build"
LABEL org.opencontainers.image.description="Build environment for the SYE course tree (SO3, virt32 / ARM 32-bit): the apt cross toolchains arm-none-eabi- and arm-linux-gnueabihf-, a prebuilt arm-linux-musleabihf MUSL toolchain for the SO3 user space, and the host packages Infrabase needs. Carries no project source."
LABEL org.opencontainers.image.source="https://github.com/smartobjectoriented/so3"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"

# Host packages come from packages.txt — the single source of truth.
# Adding a dependency there is enough.
#
# The list covers building AND running QEMU: qemu/build/qemu-system-* is
# built into the bind-mounted tree but resolves its libraries inside the
# container.

COPY packages.txt /tmp/packages.txt

RUN apt-get update \
	&& sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages.txt \
	   | xargs apt-get install -y --no-install-recommends \
	&& apt-get install -y --no-install-recommends vim nano less \
	&& rm -rf /var/lib/apt/lists/* /tmp/packages.txt

# pcpp: pre-processor used by the SO3 ITS/device-tree tooling.

RUN pip3 install --break-system-packages --no-cache-dir pcpp

# The MUSL cross toolchain for the SO3 user space. local.conf points
# IB_MUSL_PREBUILT_DIR here; when the directory exists the musl-toolchain
# recipe skips its (very long) build entirely.
#
# The kernel and U-Boot toolchains are NOT here: 32-bit builds use the
# apt prefixes arm-linux-gnueabihf- (IB_TOOLCHAIN:arm) and arm-none-eabi-
# (CONFIG_CROSS_COMPILE), both in packages.txt.
COPY --from=musl /opt/toolchains/musl /opt/toolchains/musl

# The patched QEMU. st.sh and build.sh prefer a QEMU built in the tree and
# fall back to this one, so anyone who edits QEMU's sources and runs
# `build.sh -x qemu` transparently takes over — which is what the POS
# course needs.
COPY --from=qemu /opt/qemu /opt/qemu

# U-Boot for virt32. IB_UBOOT_PATH (meta-uboot) prefers a U-Boot built in
# the tree and falls back here, so the sources need not be fetched at all
# unless someone actually works on the boot chain.
COPY --from=uboot /opt/uboot /opt/uboot

# bitbake puts the right musl bin/ on PATH itself (IB_MUSL_BIN_DIR, see
# local.conf); this is only for an interactive dbuild.sh shell.
ENV PATH=/opt/toolchains/musl/arm-linux-musleabihf/bin:${PATH}

# The build escalates a few operations (losetup, mount, mkfs, cpio with
# device nodes) through `sudo -n`. Inside a throw-away build container a
# blanket NOPASSWD rule is the simplest correct answer, and it makes the
# host-side tty_tickets problem (scripts/common/setup_sudo.sh) moot.
#
# `Defaults !authenticate` is NOT redundant with NOPASSWD. The front-end
# scripts open their session with `sudo -v`, which validates the user
# rather than a specific command: sudo then requires authentication as
# soon as ANY applicable rule asks for it — and the build user also
# matches Ubuntu's `%sudo ALL=(ALL:ALL) ALL`. Without this line,
# `sudo -n true` succeeds while `sudo -v` fails with "a terminal is
# required to read the password", and every `build.sh bsp-linux*` /
# `deploy.sh` dies at sudo_session_start.

RUN printf 'Defaults !authenticate\nALL ALL=(ALL) NOPASSWD:ALL\n' \
	> /etc/sudoers.d/build-env \
	&& chmod 0440 /etc/sudoers.d/build-env

# The tree is bind-mounted and owned by the host user; keep git quiet if
# the ids ever fail to line up.

RUN git config --system --add safe.directory '*'

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# rc file for `dbuild.sh` with no command: an interactive shell with
# env.sh already sourced (see the file for why it must be sourced there
# and not in a parent).

COPY bashrc /etc/sye-build.bashrc

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
