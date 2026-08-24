#!/usr/bin/env bash
#
# Build and deploy SO3 — kernel and user space — in one go, from anywhere
# in the tree.
#
# This is the day-to-day edit/run loop, and it replaces reaching for
# makeusr.sh by hand: that one only knows about a usr/ directory and only
# builds it, leaving the kernel and the deployment to you.
#
# Both halves are built directly (make / cmake), not through bitbake, so
# the loop stays short. The deployment, on the other hand, goes through
# `deploy.sh bsp-so3`: rendering the ITS, packing the ITB and writing the
# SD-card image is recipe work, and reimplementing it here would only
# drift. It costs a bitbake parse, and it is why this script deploys once
# at the end rather than after each half.
#
# Nothing is lost by building by hand: the kernel is built in place
# (`so3/so3/so3`) and `usr-so3:do_deploy` is nostamp, so the deploy picks
# up whatever is on disk.
#
# Copyright (c) 2026 Daniel Rossier, REDS Institute - HEIG-VD
#

set -eo pipefail

# Resolve the tree from the script's own location and the current
# directory — this is what makes the script work from any subdirectory.
# See scripts/common/setup_env.sh. It reads $IB_ROOT_DIR unguarded, and
# no other front-end script runs under `set -u`, so strict mode is
# switched on only once it has been sourced.

. "$(cd "$(dirname "$(command -v -- "$0")")" && pwd)/common/setup_env.sh"

set -u

progname="$(basename "$0")"

SO3_DIR="${IB_ROOT_DIR}/so3/so3"
USR_DIR="${IB_ROOT_DIR}/so3/usr"

DO_KERNEL=1
DO_USR=1
DO_DEPLOY=1
RECONFIGURE=0
CORES="$(nproc)"

usage()
{
	printf "Build and deploy SO3 (kernel + user space), from anywhere in the tree\n\n"
	printf "Usage: %s [-k] [-u] [-n] [-c] [-j N] [-h]\n\n" "$progname"
	printf "    -k    Kernel only (so3/so3)\n"
	printf "    -u    User space only (so3/usr)\n"
	printf "    -n    Build only, do not deploy\n"
	printf "    -c    Force a fresh configure (kernel defconfig, cmake)\n"
	printf "    -j N  Parallel jobs (default: %s)\n" "${CORES}"
	printf "    -h    This help\n\n"
	printf "With no option: kernel, then user space, then deploy.\n"
}

while getopts "kuncj:h" o; do
	case "$o" in
		k) DO_USR=0 ;;
		u) DO_KERNEL=0 ;;
		n) DO_DEPLOY=0 ;;
		c) RECONFIGURE=1 ;;
		j) CORES="$OPTARG" ;;
		h) usage; exit 0 ;;
		*) usage >&2; exit 1 ;;
	esac
done

# local.conf drives which platform — and therefore which defconfig and
# which user-space arch — this tree builds. Read it rather than guessing,
# so the script follows a platform switch without being told.

ib_var()
{
	grep -E "^[[:space:]]*$1[[:space:]]*[?:]?=" "${IB_ROOT_DIR}/build/conf/local.conf" 2>/dev/null \
		| grep -v '^[[:space:]]*#' | tail -1 \
		| sed -E 's/.*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/'
}

PLATFORM="$(ib_var IB_PLATFORM)"
PLATFORM="${PLATFORM:-virt32}"

case "${PLATFORM}" in
	virt32)   USR_ARCH="arm" ;;
	*)        USR_ARCH="aarch64" ;;
esac

DEFCONFIG="$(ib_var "IB_CONFIG:so3:${PLATFORM}")"
DEFCONFIG="${DEFCONFIG:-${PLATFORM}_defconfig}"

printf "\n[makeso3] tree=%s platform=%s\n\n" "${IB_ROOT_DIR}" "${PLATFORM}"

# --- kernel ---------------------------------------------------------------

if [ "${DO_KERNEL}" = "1" ]; then
	printf "[makeso3] kernel (%s)\n" "${DEFCONFIG}"

	cd "${SO3_DIR}"

	# Mirror the so3 recipe: configure only when there is no .config yet,
	# or when asked to. A same-arch rebuild stays incremental.

	if [ "${RECONFIGURE}" = "1" ] || [ ! -f "${SO3_DIR}/.config" ]; then
		make "${DEFCONFIG}"
	fi

	make -j"${CORES}"
fi

# --- user space -----------------------------------------------------------

if [ "${DO_USR}" = "1" ]; then
	printf "\n[makeso3] user space (%s)\n" "${USR_ARCH}"

	# makeusr.sh works on its current directory and already owns the
	# toolchain lookup, the arch marker and the local deploy. Reuse it
	# rather than duplicating a hundred lines that would drift.

	cd "${USR_DIR}"

	usr_opts=(-a "${USR_ARCH}" -j "${CORES}")
	[ "${RECONFIGURE}" = "1" ] && usr_opts+=(-c)

	"${IB_ROOT_DIR}/scripts/makeusr.sh" "${usr_opts[@]}"
fi

# --- deploy ---------------------------------------------------------------

if [ "${DO_DEPLOY}" = "1" ]; then
	printf "\n[makeso3] deploying bsp-so3\n"

	# Writing the SD-card image needs root; deploy.sh opens the sudo
	# session and may ask for a password.

	"${IB_ROOT_DIR}/scripts/deploy.sh" bsp-so3
fi

printf "\n[makeso3] done — run st.sh to boot it.\n"
