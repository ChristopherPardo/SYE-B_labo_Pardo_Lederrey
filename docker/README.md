**This directory contains the Dockerfiles related to SO3.**

All images build SO3 with the **Infrabase** (bitbake) build system. The container
holds the whole repository at `/so3`; inside it the kernel is at `/so3/so3/so3`,
the user space at `/so3/so3/usr` and the bundled LVGL at `/so3/so3/usr/lib/lvgl`.

# Developer build container — `dbuild.sh`

For day-to-day development, use [`build-env`](./build-env) driven by
`scripts/dbuild.sh` — it replaces the older "repository baked into the image"
flow for interactive work. The image carries ONLY the environment (the 32-bit
apt toolchains `arm-none-eabi-` and `arm-linux-gnueabihf-`, a prebuilt
`arm-linux-musleabihf` MUSL toolchain, host packages); the repository stays on
the host and is
bind-mounted at its **own absolute path**, so host and container builds share
one `build/tmp` interchangeably, and the container runs as the calling host
user so everything it writes stays yours.

```
./scripts/dbuild.sh build.sh bsp-so3  # run any front-end script inside
./scripts/dbuild.sh                    # interactive shell, env.sh sourced
./scripts/dbuild.sh st.sh -d           # graphical QEMU from the container
./scripts/dbuild.sh --repull           # re-fetch the published image
./scripts/dbuild.sh --build            # build it locally instead
```

The image is fetched on demand: the first command that needs it and does not
find it locally pulls the published one and tags it `sye-build:1.0`. Nothing to
install by hand.

It carries three things the tree would otherwise build for itself: the MUSL
cross toolchain (`/opt/toolchains/musl`), the patched QEMU (`/opt/qemu`) and
U-Boot for virt32 (`/opt/uboot`). Each is reproduced from its own recipe —
same sources, same patches, same options — so a tree that does build its own
gets the same thing. For all three the resolution is **tree first, image
second**: `build.sh -x qemu` or `build.sh -x uboot` takes over with nothing to
unset. That keeps 2.1 GB of QEMU sources and 190 MB of U-Boot sources out of a
student tree while leaving them one command away.

Caller environment variables are not forwarded; pass them through the
command: `./scripts/dbuild.sh env IB_FORCE_ATTACH=1 build.sh bsp-so3`.

## Pulling the image instead of building it

The image is published on the GitHub Container Registry, so nobody has to
build it — which matters, because the MUSL toolchain inside it is binutils,
gcc and musl compiled from source, roughly a quarter of an hour.

`dbuild.sh` pulls it by itself the first time it is needed, so the student
command is just `./scripts/dbuild.sh build.sh bsp-so3`. The package is public:
no `docker login` is required.

Two variables adjust the mechanism: `IB_DOCKER_IMAGE` is the working name
(default `sye-build:1.0`; set it to a full registry reference and it is pulled
as such, without re-tagging) and `IB_DOCKER_REGISTRY` is where the pull comes
from (default `ghcr.io/smartobjectoriented/sye-build:1.0`).

Publishing a new revision (maintainers):

```
gh auth refresh -h github.com -s write:packages     # once, needs write:packages
gh auth token | docker login ghcr.io -u <user> --password-stdin
./scripts/dbuild.sh --build
docker tag sye-build:1.0 ghcr.io/smartobjectoriented/sye-build:1.0
docker push ghcr.io/smartobjectoriented/sye-build:1.0
```

A package created by the first push is **private**, and GitHub exposes no REST
endpoint to change that — flip it once in the UI, under *Package settings →
Danger Zone → Change visibility*:
<https://github.com/orgs/smartobjectoriented/packages/container/package/sye-build>

### Automatic rebuilds

`.gitlab-ci.yml` at the tree root rebuilds and pushes the image whenever
`docker/build-env/**` or the musl `config.mak` changes on the default branch,
and can also be started by hand from the GitLab UI. It assembles the same
throw-away context `dbuild.sh --build` does.

GitHub Actions is not usable for this: the repository lives on reds-gitlab, and
Actions only runs on repositories hosted on GitHub.

The job needs two CI/CD variables — `GHCR_USER` and `GHCR_TOKEN`, the latter a
GitHub PAT carrying `write:packages`, and worth masking — and the `sye-image`
runner on `runnerserver`. That runner uses a **shell** executor whose
`gitlab-runner` user is in the `docker` group, so the job drives the host
daemon directly.

Do not expect docker-in-docker to work on the instance runners: `reds-calculator`
uses the docker executor but is not privileged, `docker:*-dind` cannot mount its
filesystems there, and the job dies at `docker login` with `unable to resolve
docker endpoint`. That is why the job pins a tag — untagged, the instance
runners would grab it and fail that way.

It publishes two tags: `1.0`, which moves and is what `dbuild.sh` and the
documentation pin, and `<short-sha>`, which is immutable and is what you roll
back to. A run takes about twenty minutes, nearly all of it compiling musl.

Each publish leaves the previous index untagged and adds one more `<short-sha>`
tag. `scripts/ci/ghcr-prune.py` runs at the end of the job and clears both: it
deletes the untagged leftovers and the `<short-sha>` versions past the three
most recent (`GHCR_SHA_KEEP`). It never touches a version tagged `1.0`, and it
resolves the children of every index it keeps rather than assuming untagged
means unused — pass `--dry-run` to see what it would do.

The images below remain the CI/perf-rig side of the house.

# Base build environment

- [`Dockerfile.toolchains`](./Dockerfile.toolchains) — Ubuntu image with the
  bitbake host dependencies, the SO3 build tools (dtc, u-boot-tools, mtools, QEMU
  build deps, …) and the **bare-metal kernel** cross toolchains
  (`aarch64-none-elf`, `arm-none-eabi`). The MUSL user-space toolchains are **not**
  built here — they are produced by the `meta-toolchain` layer during the build.
- [`Dockerfile.env`](./Dockerfile.env) — a thin layer over the toolchains image,
  used by the `Build` CI to compile SO3 with the repository mounted at `/so3`.

# LVGL performance test images

- [`Dockerfile.lvperf_32b`](./Dockerfile.lvperf_32b)
- [`Dockerfile.lvperf_64b`](./Dockerfile.lvperf_64b)

Images with SO3 pre-built using the `virtXX_lvperf_defconfig` configuration, used
to run [LVGL](https://lvgl.io/) performance tests under the patched QEMU.

## Getting Started

**Build** the images from the repository root. Use **`--network=host`**: the
image build fetches the components (QEMU tarball, U-Boot/AVZ git) via
Infrabase, and on hosts where the Docker *bridge* network can't resolve/reach
external mirrors (common with systemd-resolved or a VPN), the build's
`do_fetch` fails with a wget network error — host networking uses the host
resolver and works.
```bash
# 32-bit
docker build --network=host . -f docker/Dockerfile.lvperf_32b -t so3-lvperf32b
# 64-bit
docker build --network=host . -f docker/Dockerfile.lvperf_64b -t so3-lvperf64b
```

**Run** them. `--privileged` is **required**: the SD-card image is created with
`losetup`/`mkfs`/`mount` (this cannot be done during `docker build`, which is not
privileged — hence the build-time / run-time split below). Add `--network=host`
too (same reason as the build — the run-time `usr-so3` rebuild may fetch LVGL):
```bash
docker run -it --privileged --network=host -v /dev:/dev so3-lvperf64b   # or so3-lvperf32b
```

## Technical Details

- **At image-build time** (non-privileged), Infrabase builds the full BSP. On the
  virt platforms `build.sh bsp-so3` also builds the emulator (`meta-qemu`)
  automatically when its binary is still missing, so no separate `build.sh qemu`
  step is needed. It is privilege-free: it only compiles (the MUSL toolchain via
  `meta-toolchain`, the kernel, the user space, U-Boot, QEMU) and creates an empty
  `rootfs.fat`. The privileged rootfs loop-mount is deferred to `deploy.sh`.
  ```
  build.sh bsp-so3
  ```
- **At container-run time** (privileged), the entrypoint rebuilds the user space
  (picking up a mounted LVGL), creates+formats the SD-card image (`build.sh -x filesystem` —
  `losetup`/`fdisk`/`mkfs`, the privileged step that cannot run at build time),
  then `deploy.sh` assembles the FIT, populates the rootfs and writes the SD-card,
  and finally QEMU runs:
  ```
  build.sh -x usr-so3  &&  build.sh -x filesystem  &&  deploy.sh bsp-so3  &&  docker/scripts/run.sh
  ```

With `virtXX_lvperf_defconfig` the kernel runs the LVGL benchmark as its init
program; when it finishes the kernel performs a **semihosting exit**, so QEMU
(`-semihosting`) halts and the container exits with the perf output on stdout.

## Adding Additional Dependencies

To install extra dependencies without rebuilding the image, mount a shell script
at `/so3/install_dependencies.sh` (the entrypoint runs it first).

## Persistence

Each run repeats the run-time steps. To cache between runs, mount the bitbake work
tree and the boot media as volumes:

- `/so3/build/tmp` — the bitbake work tree (toolchain, QEMU, kernel, usr, sstate)
- `/so3/filesystem` — the generated SD-card image

```bash
docker run -it --privileged \
    -v /dev:/dev \
    -v "$(pwd)/../so3-build-tmp-64b:/so3/build/tmp" \
    -v "$(pwd)/../so3-filesystem-64b:/so3/filesystem" \
    so3-lvperf64b
```

> [!NOTE]
> Use separate cache volumes for the 32-bit and 64-bit images.

## Customization Options

### LVGL

The LVGL source lives at `/so3/so3/usr/lib/lvgl` and its configuration at
`/so3/so3/usr/lib/lv_conf.h`. Mount your own to benchmark them — the run-time
`build.sh -x usr-so3` rebuilds the user space against them:

```bash
docker run -it --privileged \
    -v /dev:/dev \
    -v <lvgl_path>:/so3/so3/usr/lib/lvgl \
    -v <lv_conf_path>:/so3/so3/usr/lib/lv_conf.h \
    so3-lvperf64b
```

### SO3 kernel / U-Boot

You can also override the prebuilt kernel or U-Boot binaries:

```bash
docker run -it --privileged \
    -v /dev:/dev \
    -v <patched_so3.bin>:/so3/so3/so3/so3.bin \
    -v <patched_u-boot>:/so3/u-boot/u-boot \
    so3-lvperf64b
```
