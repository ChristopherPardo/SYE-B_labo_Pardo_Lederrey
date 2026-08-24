.. _container:

===================
The build container
===================

Building this tree needs a cross toolchain and some eighty host packages, in
versions that match. The build container provides exactly that, so nothing has
to be installed on your machine and everyone builds in the same environment —
including the teaching assistants when they reproduce your problem.

The container carries **only the environment**. Your repository stays on your
machine and is bind-mounted into it, at the **same absolute path**, so:

* everything the build writes — source trees, ``build/tmp``, the images — stays
  on your disk and belongs to **you**, not to root;
* you can alternate freely between building inside the container and (if you
  ever set one up) building natively: bitbake stamps, the CMake caches and the
  ``*.attach.sha256`` manifests all record absolute paths, and an identical path
  is what keeps them valid.

Usage
=====

.. code-block:: console

   $ dbuild.sh --build                    # build (or rebuild) the image — once
   $ dbuild.sh                            # interactive shell in the container
   $ dbuild.sh build.sh bsp-so3           # run one command, then exit
   $ dbuild.sh deploy.sh bsp-so3
   $ dbuild.sh st.sh -d
   $ dbuild.sh -h                         # help

``dbuild.sh`` lives in ``scripts/``, so after ``. ./env.sh`` it is a plain
command, usable from anywhere in the tree. Your current directory is preserved
inside the container, and with no argument you get an interactive shell with
``env.sh`` already sourced:

.. code-block:: console

   $ cd so3/usr
   $ dbuild.sh
   [sye-build] ~/sye/sye_student/so3/usr $ makeso3.sh

Note the prompt: the directory you were in is the directory you land in.
``makeso3.sh`` does not care which one it is — it finds the tree by itself.

Two environment variables adjust it without editing anything:

.. code-block:: console

   $ IB_DOCKER_IMAGE=sye-build:test dbuild.sh --build
   $ IB_DOCKER_OPTS="-v /media/sdcard:/media/sdcard" dbuild.sh

What is in the image
====================

Everything is under ``docker/build-env/``:

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - File
     - Role
   * - ``Dockerfile``
     - Two stages: compile the MUSL cross toolchain, then install the
       environment. Its build context is that directory only — never the
       project root, which holds tens of GB of output.
   * - ``packages.txt``
     - The host packages, one per line, with a comment explaining each group.
       **This is the single source of truth**: adding a dependency there is all
       it takes.
   * - ``entrypoint.sh``
     - Creates an account matching your UID/GID (passed at run time, so one
       image serves everybody) and drops to it. Nothing runs as root.
   * - ``bashrc``
     - The rc file for the interactive shell; it is what sources ``env.sh`` and
       sets the ``[sye-build]`` prompt.

The toolchains this course uses, both from apt:

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - Prefix
     - Used for
   * - ``arm-none-eabi-``
     - the **SO3 kernel** — bare metal, ARM 32-bit
   * - ``arm-linux-gnueabihf-``
     - **U-Boot**
   * - ``arm-linux-musleabihf-``
     - the **user-space applications** — not from apt: compiled from source by
       the first Dockerfile stage and installed under
       ``/opt/toolchains/musl``

That last one is why the image is worth pulling. ``musl-toolchain`` builds
binutils, gcc and musl from source, a quarter of an hour per tree; the recipe
finds the one in the image and stands aside.

Two more programs are baked in for the same reason, and they are the ones that
keep your tree small:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - In the image
     - Instead of
   * - ``/opt/qemu`` — the **patched QEMU**, built from the same sources and
       patches as ``meta-qemu``
     - 2.1 GB of QEMU sources in your tree, and a compile of several minutes
       on a laptop
   * - ``/opt/uboot`` — **U-Boot** for ``virt32``, same SRCREV and same 54
       patches as ``meta-uboot``
     - 190 MB of U-Boot sources

Neither is fetched at all when the image provides it. A fresh clone therefore
goes from clone to a booting system without downloading a single upstream
tarball, and stays around 2.1 GB instead of 2.9 GB.

**The tree always wins.** For each of the three — MUSL, QEMU, U-Boot — the
build looks in your tree first and only falls back to the image. Run
``build.sh -x qemu`` or ``build.sh -x uboot`` once and yours takes over, with
nothing to unset: the sources are fetched, built, and every later command uses
them. That is what makes the image safe for a course where you *do* modify
QEMU.

.. note::

   The flip side: while you use the image's U-Boot, editing a patch under
   ``build/meta-uboot/`` changes nothing — the binary you boot was built when
   the image was. Run ``build.sh -x uboot`` to take over, or rebuild the image.

The image is **32-bit only**. SYE runs on ``virt32`` and nothing else, so the
Arm 64-bit toolchains and the ``aarch64-linux-musl`` target are not shipped —
they would add over 1.5 GB for nothing. Building a 64-bit platform inside this
container fails on a missing compiler, by design.

Where the image comes from
==========================

The image is published on the GitHub Container Registry, as a **public**
package: pulling it needs no account and no ``docker login``. And you do not
pull it yourself — ``dbuild.sh`` does, the first time a command needs it:

.. code-block:: console

   [dbuild] image 'sye-build:1.0' not found locally
   [dbuild] pulling ghcr.io/smartobjectoriented/sye-build:1.0
   [dbuild] tagged as sye-build:1.0

It is fetched under its published name and tagged ``sye-build:1.0``, the
working name every later run looks for. ``dbuild.sh --repull`` drops the local
copy and fetches it again; ``dbuild.sh --build`` builds it from
``docker/build-env/`` instead, which is what you want offline or after changing
those files.

Two environment variables adjust this without editing anything:
``IB_DOCKER_IMAGE`` is the working name (set it to a full reference and it is
pulled as such, without re-tagging), ``IB_DOCKER_REGISTRY`` is where the pull
comes from.

Two tags are published:

.. list-table::
   :header-rows: 1
   :widths: 26 74

   * - Tag
     - Meaning
   * - ``1.0``
     - What the documentation and ``dbuild.sh`` pin. It **moves**: each rebuild
       republishes it.
   * - ``<short-sha>``
     - The commit the image was built from. Immutable — pin this one to freeze
       an environment for a semester, or to go back after a bad rebuild. The
       three most recent are kept; older ones are deleted after each publish,
       so pin a digest instead if you need to go further back than that.

Rebuilds are automatic. ``.gitlab-ci.yml`` runs whenever ``docker/build-env/``
or the musl ``config.mak`` changes on the default branch, and can also be
started by hand from the GitLab UI. It builds on ``runnerserver``, whose runner
uses a shell executor with access to the host Docker daemon, and pushes both
tags. Roughly twenty minutes, most of it compiling musl. It then runs
``scripts/ci/ghcr-prune.py``, which deletes the versions the previous publish
orphaned and retires the ``<short-sha>`` tags beyond the three most recent
(``GHCR_SHA_KEEP`` changes the count). A version carrying ``1.0`` is never
touched.

Building it yourself with ``dbuild.sh --build`` remains perfectly fine — that is
what the CI does, from the same files.

Graphical programs
==================

``st.sh -d`` (the QEMU window showing the guest's framebuffer) opens a real
window from inside the container: ``dbuild.sh`` forwards your ``DISPLAY``, the X
socket and the X cookie. It works out of the box on a normal Linux session, X11
or Wayland. If a window refuses to open, see :ref:`troubleshooting`.

Hardware
========

The container runs ``--privileged`` with ``/dev`` bind-mounted, because the
storage steps need loop devices, ``mount`` and ``mkfs``. On ``virt32`` those act
on a plain image file (``IB_STORAGE_MODE = "soft"``) inside ``filesystem/``, so
nothing outside the tree is ever touched. Keep in mind all the same that the
container is **not** a sandbox: it sees your devices.

.. _container-platforms:

Linux, WSL2, macOS
==================

Everything here is developed and tested on **Linux**. The image itself builds
anywhere, but several of the mechanisms above rely on the container sharing the
host's kernel — and on macOS and Windows, Docker Desktop runs containers inside
a Linux virtual machine, so "the host" they see is that VM, not your machine:

.. list-table::
   :header-rows: 1
   :widths: 30 14 28 28

   * -
     - Linux
     - Windows + WSL2
     - macOS
   * - Build
     - yes
     - yes, with the tree **inside** the WSL2 filesystem (``/home/…``); on
       ``/mnt/c/…`` it is very slow
     - works, but slow
   * - QEMU + graphics
     - yes
     - yes, through WSLg (Windows 11)
     - needs XQuartz and a TCP ``DISPLAY``; the socket forwarding used here does
       not apply
   * - The GDB port (1234)
     - yes
     - yes
     - no — it is published inside the VM

Recommended: **Windows → WSL2**, with the tree in the WSL2 filesystem.
**macOS → a Linux virtual machine**, which is less friction than Docker Desktop
for the graphical labs.

Adding a dependency
===================

If something is missing from the image, add it to ``docker/build-env/packages.txt``
(in the right group, with a short comment saying why) and rebuild:

.. code-block:: console

   $ dbuild.sh --build

Please do not install packages by hand inside a running container: the container
is thrown away on exit, and the next person hits your problem again.
