#!/bin/sh

# Run an Infrabase command inside the build container.
#
# The container provides the ENVIRONMENT (cross toolchains, host
# packages, CMake, Python); the repository stays on the host and is
# bind-mounted, so sources, build/tmp and the produced images remain
# exactly where they are and stay owned by the calling user.
#
# Usage:
#   dbuild.sh --repull             Re-pull the published image, discarding
#                                  the local copy
#   dbuild.sh --build              Build (or rebuild) the image
#   dbuild.sh                      Interactive shell inside the container
#   dbuild.sh build.sh bsp-so3    Run a build
#   dbuild.sh deploy.sh bsp-so3   Deploy it
#   dbuild.sh st.sh -d             Run it under QEMU, graphical
#
# The command runs with the project root bind-mounted at its OWN
# absolute path and the current directory preserved, so a tree can be
# built from inside or outside the container interchangeably: bitbake
# stamps, CMake caches and the *.attach.sha256 manifests all record
# absolute paths and would otherwise be invalidated on every switch.
#
# The image is fetched on demand: the first command that needs it and does
# not find it locally pulls the published one and tags it under the working
# name. Nothing to install by hand, no environment variable to remember.
#
# Environment overrides:
#   IB_DOCKER_IMAGE     working image name:tag (default: sye-build:1.0)
#   IB_DOCKER_REGISTRY  published image to pull when the working one is
#                       missing (default: ghcr.io/smartobjectoriented/sye-build:1.0)
#   IB_DOCKER_OPTS      extra `docker run` options
#
# Copyright (c) 2026 REDS Institute - HEIG-VD

set -e

progname=$(basename "$0")

IB_DOCKER_IMAGE=${IB_DOCKER_IMAGE:-sye-build:1.0}
IB_DOCKER_REGISTRY=${IB_DOCKER_REGISTRY:-ghcr.io/smartobjectoriented/sye-build:1.0}

# Resolve the project root from this script's own location so dbuild.sh
# works from anywhere inside the tree.
#
# `pwd -P` (physical path) on purpose: a tree is commonly reached through
# a symlink (~/edgemtech/edgem1 -> products/edgem1/edgem1), and the cwd
# check below and the bind mount both work on plain strings. Without
# resolving, entering by the symlink while the script resolves the real
# path aborts with "current directory is outside <tree>".

IB_ROOT=$(cd "$(dirname "$(command -v -- "$0")")/.." && pwd -P)
CONTEXT="$IB_ROOT/docker/build-env"

pr_usage()
{
	printf "Run an Infrabase command inside the build container\n\n"
	printf "Usage: %s [--repull|--build] [<command> [args...]]\n\n" "$progname"
	printf "    --repull    Re-pull %s, replacing the local copy\n" "$IB_DOCKER_REGISTRY"
	printf "    --build     Build (or rebuild) the %s image locally\n" "$IB_DOCKER_IMAGE"
	printf "    <command>   Command to run inside the container (default: an\n"
	printf "                interactive shell). env.sh is sourced first, so\n"
	printf "                scripts/ and bitbake are on PATH.\n\n"
	printf "Examples:\n"
	printf "    %s --build\n" "$progname"
	printf "    %s build.sh bsp-so3\n" "$progname"
	printf "    %s deploy.sh bsp-so3\n" "$progname"
	printf "    %s st.sh -d\n" "$progname"
}

if ! command -v docker >/dev/null 2>&1; then
	printf "%s: docker is not installed\n" "$progname" >&2
	exit 1
fi

# Fetch the published image and give it the working name. Kept separate from
# the run path so --repull can force it.
#
# A working name that already carries a registry host is taken at face value
# and pulled as such: someone who set IB_DOCKER_IMAGE to a full reference
# means it, and re-tagging over their choice would be surprising.

pull_image()
{
	case "$IB_DOCKER_IMAGE" in
		*[.:]*/*)
			printf "[dbuild] pulling %s\n" "$IB_DOCKER_IMAGE"
			docker pull "$IB_DOCKER_IMAGE"
			return
			;;
	esac

	printf "[dbuild] pulling %s\n" "$IB_DOCKER_REGISTRY"

	if ! docker pull "$IB_DOCKER_REGISTRY"; then
		printf "\n%s: could not pull %s.\n" "$progname" "$IB_DOCKER_REGISTRY" >&2
		printf "         Check the network, or build the image locally: %s --build\n" \
			"$progname" >&2
		return 1
	fi

	docker tag "$IB_DOCKER_REGISTRY" "$IB_DOCKER_IMAGE"
	printf "[dbuild] tagged as %s\n" "$IB_DOCKER_IMAGE"
}

case "$1" in
	-h|--help)
		pr_usage
		exit 0
		;;
	--repull)
		# Dropping the local copy is the point — `docker pull` on an
		# unchanged tag is a no-op. But that copy may be one someone
		# built with --build, which no pull can bring back, so say so
		# rather than discarding it silently.
		if docker image inspect "$IB_DOCKER_IMAGE" >/dev/null 2>&1; then
			printf "[dbuild] replacing the local %s\n" "$IB_DOCKER_IMAGE"
			printf "         (a locally built image is lost; rebuild it with %s --build)\n" \
				"$progname"
		fi

		docker rmi -f "$IB_DOCKER_IMAGE" >/dev/null 2>&1 || true
		pull_image
		exit $?
		;;
	--build)
		printf "[dbuild] building %s from %s\n" "$IB_DOCKER_IMAGE" "$CONTEXT"

		# Context is docker/build-env only — never the project root,
		# which carries tens of GB of build output.
		#
		# The musl and qemu stages need files that live with their
		# recipes and must NOT be duplicated in the context (they would
		# silently drift from the ones bitbake uses): musl's config.mak
		# and the QEMU patch series. Assemble a throw-away context
		# instead — the build-env directory plus those.

		musl_config="$IB_ROOT/build/meta-toolchain/recipes-toolchain/musl/files/config.mak"
		if [ ! -f "$musl_config" ]; then
			printf "%s: %s not found\n" "$progname" "$musl_config" >&2
			exit 1
		fi

		qemu_patches="$IB_ROOT/build/meta-qemu/recipes-qemu/qemu/files/0001-qemu-8.2.2-r0"
		if [ ! -d "$qemu_patches" ]; then
			printf "%s: %s not found\n" "$progname" "$qemu_patches" >&2
			exit 1
		fi

		uboot_patches="$IB_ROOT/build/meta-uboot/recipes-uboot/uboot/files/0001-uboot-2022.04-r0"
		if [ ! -d "$uboot_patches" ]; then
			printf "%s: %s not found\n" "$progname" "$uboot_patches" >&2
			exit 1
		fi

		tmpctx=$(mktemp -d)
		trap 'rm -rf "$tmpctx"' EXIT INT TERM
		cp -a "$CONTEXT"/. "$tmpctx"/
		cp "$musl_config" "$tmpctx/musl-config.mak"
		mkdir -p "$tmpctx/qemu-patches"
		cp "$qemu_patches"/*.patch "$tmpctx/qemu-patches/"
		mkdir -p "$tmpctx/uboot-patches"
		cp "$uboot_patches"/*.patch "$tmpctx/uboot-patches/"

		docker build -t "$IB_DOCKER_IMAGE" "$tmpctx"
		exit $?
		;;
esac

# No image yet? Fetch it rather than sending the user away to read a
# message. Building it locally stays available with --build.

if ! docker image inspect "$IB_DOCKER_IMAGE" >/dev/null 2>&1; then
	printf "[dbuild] image '%s' not found locally\n" "$IB_DOCKER_IMAGE"
	pull_image || exit 1
fi

# The cwd is reused verbatim inside the container and only $IB_ROOT is
# mounted, so it has to live inside the tree.

cwd=$(pwd -P)
case "$cwd" in
	"$IB_ROOT"|"$IB_ROOT"/*) ;;
	*)
		printf "%s: current directory is outside %s — cd into the tree first\n" \
			"$progname" "$IB_ROOT" >&2
		exit 1
		;;
esac

# Build the docker argv by PREPENDING to the user command, so the
# command always stays last and no quoting is lost.
#
# No command: an interactive shell driven by the image's rc file, which
# sources env.sh IN that shell so its cd/pushd/popd wrappers and
# ib_autoswitch_* functions exist (a parent that sources env.sh then
# execs bash would pass on the variables but lose the functions).
#
# With a command: source env.sh first, because the front-end scripts
# refuse to reconfigure the environment in a non-interactive context.

if [ $# -eq 0 ]; then
	set -- "$IB_DOCKER_IMAGE" bash --rcfile /etc/sye-build.bashrc -i
else
	set -- "$IB_DOCKER_IMAGE" bash -c \
		'cd "$2" && . ./env.sh >/dev/null 2>&1; cd "$1"; shift 2; exec "$@"' \
		dbuild "$cwd" "$IB_ROOT" "$@"
fi

set -- -e IB_TREE="$IB_ROOT" -e IB_CWD="$cwd" "$@"

# Hardware deployment: make any IB_HTTP_DEPLOY_PATH feed directory
# visible at its own path so `deploy.sh` can publish into it from inside
# (IB_STORAGE_MODE=http). This serves the verdin-imx8mp TEZI flow; on the
# soft/hard storage platforms it is a no-op.
# IB_STORAGE_MODE=hard needs no extra wiring: /dev is already
# bind-mounted and the container is privileged (it writes the HOST's
# device, so double-check IB_STORAGE_DEVICE).
#
# The DEFAULT feed lives inside the tree (IB_HTTP_DEPLOY_PATH in
# local.conf), which is already bind-mounted, so this loop does nothing
# for it. It only matters for a build/conf/site.conf that redirects the
# feed out of the tree.
#
# A snap-packaged Docker cannot do this: the confined daemon only reaches
# $HOME (and a few allowed paths), so bind-mounting e.g. /var/www/html
# fails with "mkdir /var/www: read-only file system". Skip the mount
# there rather than making every invocation fail, and say so once.

_snap_docker=0
case "$(command -v docker)" in
	/snap/*) _snap_docker=1 ;;
esac

# The client path is not proof either way: the docker snap also ships a
# /usr/bin/docker wrapper, so a confined daemon can hide behind an
# ordinary-looking binary. Ask the daemon itself — a snap daemon keeps
# its root under /var/snap. Only worth doing when the path check missed.

if [ "$_snap_docker" = "0" ]; then
	case "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)" in
		/var/snap/*|/snap/*) _snap_docker=1 ;;
	esac
fi

for _feed in $(sed -n 's/^[[:space:]]*IB_HTTP_DEPLOY_PATH[^=]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
		"$IB_ROOT/build/conf/local.conf" "$IB_ROOT/build/conf/site.conf" \
		2>/dev/null | sort -u); do
	# Tree-relative defaults are already inside the bind-mounted tree, and
	# ${...} references are not expanded here — skip both.
	case "$_feed" in
		*'${'*)            continue ;;
		"$IB_ROOT"|"$IB_ROOT"/*) continue ;;
	esac

	[ -d "$_feed" ] || continue

	case "$_feed" in
		"$HOME"/*) ;;
		*)
			if [ "$_snap_docker" = "1" ]; then
				printf '%s: skipping bind mount of %s (snap Docker cannot mount outside $HOME) — publish the TEZI feed from the host, or install Docker from the apt repository\n' \
					"$progname" "$_feed" >&2
				continue
			fi
			;;
	esac

	set -- -v "$_feed:$_feed" "$@"
done

# Forward the ssh-agent when present, so a git fetch over SSH (private
# submodules) works from inside. Nothing is copied into the image.

if [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
	set -- -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
		-v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" "$@"
fi

# Forward the X11 display for the graphical QEMU launcher (st.sh -d).
#
# The X cookie must come along with the socket: the container user has a
# different HOME, so ~/.Xauthority would not be found, and under Wayland
# the cookie lives outside HOME anyway (XWayland puts it in
# /run/user/<uid>/). Mount the file at its own path and point XAUTHORITY
# at it; without this the GTK window dies with "Authorization required".

if [ -n "$DISPLAY" ] && [ -d /tmp/.X11-unix ]; then
	set -- -e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix "$@"

	_xauth=${XAUTHORITY:-$HOME/.Xauthority}
	if [ -f "$_xauth" ]; then
		set -- -e XAUTHORITY="$_xauth" -v "$_xauth:$_xauth:ro" "$@"
	fi
fi

# Always keep stdin attached (-i): without it Docker gives the container
# /dev/null, so piping into a containerised command silently delivers
# nothing — e.g. `printf 'cmd\n' | dbuild.sh st.sh` never reaches the
# guest console. Harmless when there is no input: the command just sees
# EOF. Allocate a tty (-t) only for a real terminal, so CI logs stay
# clean.

if [ -t 0 ] && [ -t 1 ]; then
	set -- -it "$@"
else
	set -- -i "$@"
fi

# shellcheck disable=SC2086
[ -n "$IB_DOCKER_OPTS" ] && set -- $IB_DOCKER_OPTS "$@"

# --privileged + /dev: the storage steps (build.sh filesystem, deploy.sh)
# need loop devices, mount and mkfs. Loop devices are a HOST-kernel
# resource, so concurrent builds on one machine contend for them exactly
# as they do outside a container.
#
# --network host: keeps st.sh's slirp port forwards (guest ssh on 2222),
# the GDB stub and the Sense HAT bridge (4442) reachable from the host
# without publishing ports, and lets the recipes fetch through the host
# resolver.

set -- --rm \
	--privileged \
	--network host \
	-v /dev:/dev \
	-v "$IB_ROOT:$IB_ROOT" \
	-w "$cwd" \
	-e HOST_UID="$(id -u)" \
	-e HOST_GID="$(id -g)" \
	-e TERM="${TERM:-xterm}" \
	"$@"

docker run "$@"
_rc=$?

# The TEZI feed server has to run on the HOST: the container is --rm, so a
# server started inside it dies with the command that started it. It shares
# the host network namespace (--network host above), but not its lifetime.
#
# Run this after the container rather than before, so the very first
# `dbuild.sh deploy.sh ...` — which creates the feed inside the container —
# leaves a serving feed behind too. Idempotent, and a no-op when nothing has
# been published yet or a server is already up.

"$IB_ROOT/scripts/tezi-feed-serve.sh" --ensure

exit $_rc
