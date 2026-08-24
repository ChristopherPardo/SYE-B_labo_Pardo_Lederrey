.. _user_space:

==========
User space
==========

The SO3 user space is a small, self-contained set of applications built against
the **MUSL** C library. Everything lives under ``so3/usr/``.

The MUSL C library
==================

SO3 uses `MUSL <MUSL_>`__ as its libc for user applications — a small, clean and
static-friendly implementation well suited to embedded systems. Not every libc
function is enabled; functions are pulled in as the need arises. More complex
facilities (for example full ``pthreads``) are intentionally kept minimal.

Applications are linked **statically** against MUSL, so each executable is
self-contained.

**C++** applications are supported too: the programs under
``so3/usr/src/tests/`` are C++ and exercise classes, exceptions and dynamic
allocation on top of the same toolchain.

Build system (CMake)
====================

The user space is built with **CMake** and the MUSL cross toolchain by the
``usr-so3`` recipe (``meta-usr``). The toolchain (``arm-linux-musleabihf``) is
produced by ``meta-toolchain``, so there is no manual toolchain step. Build and
(re)deploy the user space with:

.. code-block:: console

   makeso3.sh -u            # all three steps below, in one command

or, recipe by recipe:

.. code-block:: console

   build.sh -x usr-so3      # configure + cross-compile (CMake + MUSL)
   deploy.sh -x usr-so3     # repopulate so3/rootfs/rootfs.fat with the apps
   deploy.sh bsp-so3        # repack rootfs into the FIT image + write the boot media

The recipe configures and builds under ``so3/usr/build/`` and gathers the
deployable, statically-linked ``*.elf`` binaries for the root filesystem. Adding
an application means dropping a C file in ``so3/usr/src/`` and referencing it from
the relevant ``CMakeLists.txt``.

Applications
============

The standard applications in ``so3/usr/src/`` include:

.. flat-table::
   :header-rows: 1
   :widths: 22 78

   * - Program
     - Role
   * - ``init.elf``
     - the **init** process: reads ``commands.ini`` and launches the shell
   * - ``sh.elf``
     - the interactive **shell** (the ``/ %`` prompt)
   * - ``ls`` / ``more`` / ``cat`` / ``touch`` / ``mkdir`` / ``rmdir`` / ``rm`` / ``mv`` / ``cp``
     - basic file utilities (``ls`` supports ``-l``; ``rm`` supports ``-r`` / ``-f``)
   * - ``time``
     - simple timing utility
   * - ``thread_example`` / ``logs_example`` / ``mydev_test``
     - API and subsystem demonstrations
   * - ``hello-world`` / ``class-test`` / ``stdlib-test`` / ``exception-test`` /
       ``allocation-test`` / ``threads-test`` / ``files-test``
     - the **C++** example and test programs of ``so3/usr/src/tests/``, built by
       default (CMake option ``WITH_TESTS``, ``ON``)
   * - ``fb_test`` / ``lvgl_*``
     - graphical programs, drawing on ``/dev/fb`` in the QEMU window
       (``st.sh -d``)

User-space libraries used by the applications live in ``so3/usr/lib/``.

File timestamps are real: the kernel reads a **PL031 real-time clock** (QEMU
virt exposes one at ``0x09010000``, seeded from the host) so ``gettimeofday`` /
``clock_gettime(CLOCK_REALTIME)`` return wall-clock time. Newly written files get
the current time (FatFS ``get_fattime``), and ``touch`` refreshes an existing
file's modification time via the ``utimensat`` syscall.

Init and the shell
==================

When the kernel hands over to user space, the root process ``execve()``\ s
``init.elf``. Init reads a small ``commands.ini`` script and runs it line by
line; a typical script prints a banner and starts the shell:

.. code-block:: text

   echo SO3 Init Program :)
   shell

The shell then presents a prompt showing the current working directory (e.g.
``/ %`` at the root, ``/dev %`` after ``cd dev``) and runs commands by forking
and ``execve()``\ -ing the corresponding ``.elf``. A bare command name (no
``/``) is looked up in the root filesystem — all executables live there and
there is no ``PATH`` — while a name containing ``/`` is resolved against the
current directory. It supports:

.. flat-table::
   :header-rows: 1
   :widths: 32 68

   * - Syntax
     - Meaning
   * - ``cmd arg1 arg2``
     - run ``cmd.elf`` with arguments
   * - ``cmd1 | cmd2 | cmd3``
     - pipeline (any number of stages)
   * - ``cmd > file`` / ``cmd >> file``
     - redirect stdout (truncate / append)
   * - ``cmd < file``
     - redirect stdin from a file
   * - ``cmd &``
     - run in the background (reaped on the next prompt)
   * - ``'literal'`` / ``"…$VAR…"``
     - single quotes (literal) / double quotes (with expansion)
   * - ``$VAR`` / ``${VAR}``
     - environment variable expansion
   * - ``exit`` / ``env`` / ``setenv`` / ``kill`` / ``history`` / ``cd`` / ``pwd``
     - builtins

Operators (``| < > >> &``) must be surrounded by whitespace. Built-in
``setenv NAME VALUE`` sets a variable (``setenv NAME`` unsets it) and ``env``
lists the environment. ``cd`` / ``pwd`` change and print the working directory
(see the note below).

When stdin is the console the shell provides **interactive line editing**: a
``HIST_MAX``-entry command **history** (Up / Down arrows, listed by the
``history`` builtin), **cursor movement** (Left / Right, Home / End) and mid-line
insert/backspace. It does this by briefly switching
the console to raw mode (clearing ``ICANON``/``ECHO`` via the ``TCSETS`` ioctl
the kernel's console driver implements) for the duration of the line edit,
then restoring canonical mode so spawned programs see a normal cooked terminal.
On non-tty input (e.g. ``init`` feeding ``commands.ini``) it falls back to plain
line reading.

.. note::

   Each process has a **current working directory** (``pcb->cwd``, default
   ``/``, inherited across ``fork()`` and preserved across ``execve()``). The
   ``chdir`` / ``getcwd`` syscalls back the ``cd`` / ``pwd`` builtins, and the
   VFS resolves relative paths (and ``.`` / ``..``) against the cwd before
   handing an absolute path to the filesystem. With the default cwd ``/`` a bare
   ``foo`` still resolves to ``/foo``, so existing absolute-from-root behaviour
   is unchanged.

Root filesystem
===============

The applications are delivered through a root filesystem. In the default
(ramfs) configuration this is a FAT image, ``so3/rootfs/rootfs.fat``, built by the
``rootfs-so3`` recipe (``meta-rootfs``) from the freshly built user binaries.
``deploy.sh bsp-so3`` packs it into the FIT image and writes it to
the SD-card (:ref:`getting_started`); ``build.sh bsp-so3`` does the whole
build + image in one step. The FAT image can be inspected on the host (e.g. with
``mtools``) — useful when debugging what actually ended up on the target.

.. _MUSL: https://musl.libc.org
