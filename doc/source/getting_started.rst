.. _getting_started:

===============
Getting started
===============

This page takes you from a fresh clone to a booted system. Budget an hour for
the first run: the build compiles a cross toolchain, a root filesystem and an
emulator from source. Everything after that is incremental and fast.

What you need
=============

* **Linux** (Ubuntu 24.04 is what everything is tested on). On Windows use
  **WSL2** with the tree inside the WSL2 filesystem; on macOS a Linux VM is the
  path of least resistance — see :ref:`container-platforms`.
* **Docker**, and your user in the ``docker`` group:

  .. code-block:: console

     $ sudo usermod -aG docker $USER      # then log out and back in
     $ docker run --rm hello-world        # must work without sudo

* About **20 GB** of free disk space, and a network connection for the first
  build (the recipes fetch U-Boot, QEMU and the MUSL toolchain sources).

You do **not** need to install any cross compiler: the build container carries
all of them.

Get the tree
============

.. code-block:: console

   $ git clone <repository-url> sye_student
   $ cd sye_student
   $ . ./env.sh

``env.sh`` must be sourced **from the root of the tree** — it takes the tree's
location from your current directory. It puts ``scripts/`` and ``bitbake`` on
your ``PATH``, so from then on ``build.sh``, ``deploy.sh``, ``st.sh`` and
``dbuild.sh`` work as plain commands, from anywhere inside the tree. Do it once
per terminal.

Every script prints a banner telling you which tree and platform it is about to
act on. Get in the habit of reading it:

.. code-block:: console

   [infrabase] bsp-so3  root=/home/you/sye/sye_student  platform=virt32

Get the container
=================

Everything is built inside a container, so the only thing you install on your
machine is Docker. There is nothing to fetch by hand: the first command that
needs the image pulls it and keeps it.

.. code-block:: console

   $ dbuild.sh arm-linux-musleabihf-gcc --version
   [dbuild] image 'sye-build:1.0' not found locally
   [dbuild] pulling ghcr.io/smartobjectoriented/sye-build:1.0
   [dbuild] tagged as sye-build:1.0
   arm-linux-musleabihf-gcc (GCC) 12.4.0

The image is public: no GitHub account, no ``docker login``. It is about 3 GB,
so that first command takes a few minutes on a decent connection; every one
after it starts instantly, using the local copy.

To force a fresh download later — a new image was published, or yours is
suspect:

.. code-block:: console

   $ dbuild.sh --repull

That compiler is the point of pulling rather than building. It is binutils, gcc
and musl compiled from source: about a quarter of an hour, which the image
spares you. When you build the user space, the ``musl-toolchain`` recipe finds
it and says so:

.. code-block:: text

   musl cross toolchain 'arm-linux-musleabihf' provided by the environment (/opt/toolchains/musl/arm-linux-musleabihf/bin) — skipping the build.

.. note::

   The image is **32-bit only**, which is all this course needs. Building a
   64-bit platform inside it fails on a missing compiler, on purpose.

If you would rather build the image yourself — you are offline, or you changed
something under ``docker/build-env/`` — that works too and produces the same
thing:

.. code-block:: console

   $ dbuild.sh --build

It is done **once**; repeat it only when ``docker/build-env/`` changes. Without
``IB_DOCKER_IMAGE`` set, ``dbuild.sh`` looks for a local ``sye-build:1.0``, which
is exactly what that command produces. See :ref:`container` for what is inside,
which tags are published, and how rebuilds happen.

Choose the platform
===================

The target is selected in ``build/conf/local.conf`` by a single variable, and it
is already set for you:

.. code-block:: text

   IB_PLATFORM ?= "virt32"

That is the only platform this course uses — leave it alone. The kernel
configuration and the boot image that go with it are wired up next to it, and
you should not need to touch those either:

.. code-block:: text

   IB_CONFIG:so3:virt32     ?= "virt32_fb_defconfig"     # kernel defconfig
   IB_TARGET_ITS:so3:virt32 ?= "virt32_so3"              # FIT image to assemble

Build, deploy, run
==================

Three steps, always in this order:

.. code-block:: console

   $ dbuild.sh build.sh bsp-so3          # compile everything
   $ dbuild.sh build.sh -x filesystem    # create the SD-card image (once)
   $ dbuild.sh deploy.sh bsp-so3         # fill it and write the boot image
   $ dbuild.sh st.sh                     # boot it under QEMU

* **build** compiles the whole dependency tree: U-Boot, the SO3 kernel, the
  MUSL toolchain, the user-space applications and the root filesystem, and — the
  first time — the patched QEMU.
* **filesystem** creates and partitions the empty SD-card image
  (``filesystem/sdcard.img.virt32``). It is a **one-off**: later builds and
  deploys reuse it.
* **deploy** turns what was compiled into something bootable: it assembles the
  FIT image (``so3/images/virt32_so3.itb``), writes it to the boot partition and
  copies the root filesystem.
* **st.sh** starts QEMU on that image. You land on the shell prompt — ``/ %``,
  the current working directory followed by a percent sign — with a shell
  running on your own operating system.

Leave QEMU with ``Ctrl-A x``.

Working in the container
========================

Prefixing every command with ``dbuild.sh`` gets old. Run it with no argument
and you get an interactive shell inside the container, with ``env.sh`` already
sourced and the tree at the very same path:

.. code-block:: console

   $ dbuild.sh
   [sye-build] ~/sye/sye_student $ makeso3.sh
   [sye-build] ~/sye/sye_student $ st.sh -d
   [sye-build] ~/sye/sye_student $ exit

``makeso3.sh`` is the loop you will spend the semester in: it rebuilds the
kernel and the user space and deploys them, in one command, from wherever you
happen to be in the tree. ``build.sh`` and ``deploy.sh`` are still there when
you want to drive one recipe at a time — see :ref:`build_system`.

This is how most people work: edit with your usual editor **outside** the
container, build and run **inside** it. Nothing is copied — it is the same
files, and everything the build produces stays yours.

Did it work?
============

After a successful deploy you should have:

.. code-block:: console

   $ ls filesystem/
   sdcard.img.virt32   work

   $ ls so3/images/
   virt32_so3.itb

and ``st.sh`` should show U-Boot loading the FIT image, then the kernel booting,
then the ``/ %`` prompt. If any of that is missing, go to
:ref:`troubleshooting`.

Next steps
==========

* :ref:`build_system` — what those recipes actually are, and the fast loops that
  save you from rebuilding the world for a one-line change.
* :ref:`running` — the graphical mode, the framebuffer applications, and
  debugging with GDB.
