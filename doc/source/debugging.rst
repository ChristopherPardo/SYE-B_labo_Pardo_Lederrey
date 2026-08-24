.. _debugging:

=============
Debugging SO3
=============

SO3 runs under an emulator, and that is a luxury: the debugger can stop the
machine at its very first instruction, single-step through the MMU being turned
on, and inspect any address the processor can reach. QEMU's built-in **GDB stub**
is the day-to-day tool.

Debug symbols
=============

The build produces two kernel files, and the distinction matters:

.. flat-table::
   :header-rows: 1
   :widths: 30 70

   * - File
     - What it is
   * - ``so3/so3/so3``
     - the linked **ELF**, with the full symbol table and the debug information.
       This is what you give to GDB.
   * - ``so3/so3/so3.bin``
     - the stripped raw binary, packed into the FIT image. This is what actually
       runs.

The two are built from the same objects, so the addresses match: GDB reads the
ELF, the target executes the ``.bin``.

User applications keep their symbols too — the statically linked ELF of each one
is under ``so3/usr/build/deploy/`` (``sh.elf``, ``ls.elf``, …).

Attaching GDB
=============

``st.sh`` always starts QEMU with a GDB stub and prints the port:

.. code-block:: text

   GDB port:  1234

(1234 plus the number of emulators already running, so two students on one
machine — or two of your own sessions — do not collide.)

To catch anything that happens during boot, freeze the machine at reset with
QEMU's ``-S``; ``st.sh`` forwards it:

.. code-block:: console

   $ dbuild.sh st.sh -S

Then, from a second terminal:

.. code-block:: console

   $ cd so3/so3
   $ gdb-multiarch -q \
        -ex 'file so3' \
        -ex 'target remote :1234' \
        -ex 'break kernel_start' \
        -ex 'continue'

Use **gdb-multiarch** (or any ARM-capable GDB): your host GDB does not know the
ARM instruction set. The tree ships a ``gdbinit`` at its root as a starting
point.

.. note::

   QEMU is stopped, not the guest's *user program*. Until the kernel has created
   the first process, everything you see is the kernel; a breakpoint in
   ``sh.elf`` will only be meaningful once you have loaded that program's
   symbols too (``add-symbol-file``).

Debugging from VSCode
=====================

The tree carries a ``.vscode/`` directory with two launch configurations —
*QEMU Debug SO3* (kernel, symbols from ``so3/so3``) and *QEMU Debug USR* (a user
application). Both drive ``gdb-multiarch`` against ``localhost:1234``, which is
the same stub as above with breakpoints and variable inspection in the editor.

.. warning::

   These configurations predate the current build system: their tasks still call
   ``./st`` and ``make``, and the user-space path is the old ``usr/build/deploy``
   rather than ``so3/usr/build/deploy``. Check them against your tree before
   relying on them.

Breakpoints worth knowing
=========================

.. flat-table::
   :header-rows: 1
   :widths: 38 62

   * - Symbol
     - What it marks
   * - ``kernel_start``
     - the start of kernel bring-up, in C
   * - ``memory_init`` / ``devices_init``
     - memory and device initialisation
   * - ``syscall_interrupt``
     - a system call entering the kernel (assembly)
   * - ``syscall_handle``
     - the dispatch, once the number is known
   * - ``data_abort`` / ``prefetch_abort``
     - a memory fault
   * - ``schedule`` / ``__switch_to``
     - the scheduler picking a thread, and the context switch itself
   * - ``create_root_process`` / ``ret_from_fork``
     - the transition into user space

When it faults
==============

On a data or prefetch abort the kernel prints the fault and stops. Three
registers tell the story, and they are the ARMv7 equivalents of what any OS
reports:

.. flat-table::
   :header-rows: 1
   :widths: 22 78

   * - Register
     - Meaning
   * - ``DFAR`` / ``IFAR``
     - the **address** that faulted (data / instruction)
   * - ``DFSR`` / ``IFSR``
     - the **reason**: translation fault (nothing mapped), permission fault
       (mapped, but not for this privilege level or not writable), alignment …
   * - ``lr`` of the frame
     - the instruction that did it

To find that instruction, disassemble the kernel ELF and look the address up:

.. code-block:: console

   $ arm-none-eabi-objdump -d so3/so3/so3 | less

A *translation fault* at a small address is usually a NULL dereference; a
*permission fault* at an address above ``0xC0000000`` from user code is a program
that tried to touch the kernel — which is the protection working, not a bug.

Printing from the kernel
========================

``printk()`` writes to the console through the serial driver, and is the right
tool for anything you want to see across a whole boot rather than at one
breakpoint. Before the console is up, ``lprintk()`` writes straight to the UART.
The verbosity is a build option (``CONFIG_LOG_LEVEL``), so a noisy subsystem can
be turned down without editing it.
