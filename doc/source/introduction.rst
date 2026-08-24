.. _introduction:

===================
Introduction to SO3
===================

**SO3** (*Smart Object Oriented*) is the operating system you work on in this
course. It is a real one — a user/kernel split, an MMU, processes and threads, a
scheduler, a filesystem, signals and pipes — and it is small enough that you can
read the subsystem you are modifying in an afternoon.

SO3 is the result of several years of research and development at the
`REDS <REDS_>`__ (Reconfigurable Embedded Digital Systems) Institute of
`HEIG-VD <HEIG-VD_>`__, in the field of embedded operating systems for ARM
systems. It was publicly released in early 2020 and its source lives on GitHub:
`smartobjectoriented/so3 <so3_github_>`__.

`Prof. Daniel Rossier <DRE_>`__ started the development of an operating system in
2013, in the context of a Bachelor lecture on porting operating systems to
embedded platforms. It has evolved constantly since and became SO3 in 2018.

Why a teaching OS at all
========================

Reading Linux to learn how an operating system works is a losing proposition:
the mechanism you are after is buried under thirty years of portability layers,
optimisations and special cases. Toy kernels have the opposite problem — they
are readable because they left out the parts that make an OS hard.

SO3 sits in between. It keeps the mechanisms that matter and nothing else:

* a genuine **user/kernel separation** — user code runs unprivileged and cannot
  touch the kernel except through a system call;
* a real **MMU** — each process has its own address space, built from real page
  tables, and a wrong pointer really does take a fault;
* **processes and threads** with ``fork()``, ``execve()``, a scheduler and
  preemption on a timer tick;
* a **filesystem**, **pipes** and **signals**.

Every one of those is something you will modify during the labs. The kernel
builds from scratch in a few seconds, so the edit/build/run loop is short enough
that experimenting is cheap.

What you run
============

This course uses SO3 in its **standalone** configuration: the kernel owns the
machine, running in the privileged mode of an ARM 32-bit processor, with user
applications in unprivileged mode above it. There is nothing underneath it — no
hypervisor, no host OS.

The machine is emulated. **QEMU** has been used at REDS since 2006 and is a
crucial tool for grasping operating-system concepts: the whole machine is
inspectable, a crash costs you a rebuild rather than a board, and the debugger
can stop the processor at its very first instruction. The target is QEMU's
``virt`` machine with a Cortex-A15 (ARMv7) — see :ref:`running`.

.. note::

   The same source tree can also be built as the **AVZ** hypervisor and as an
   **SO3 capsule**, part of the SOO research framework. Neither is used here, and
   this documentation ignores both.

Approach and philosophy
=======================

The philosophy of SO3 is to keep the OS **as compact as possible**: small enough
to be a reasonable-complexity teaching platform, yet complete enough for
industrial prototyping.

SO3 does not reinvent the wheel: it draws on long experience with other
operating systems. It is mainly inspired by Linux — its build system is based on
**Kbuild**, and a few well-proven mechanisms (the ``struct list_head`` linked
lists and related macros, *bitops*, common type definitions) come from Linux.
This is also why SO3 is released under the **GPLv2** licence, and why what you
learn here transfers directly when you later read Linux.

Where to go next
================

* :ref:`architecture` — the user/kernel split, the source tree, the address
  space and the boot sequence.
* :ref:`kernel` — the subsystems themselves: memory, processes and threads,
  scheduling, system calls, IPC, the filesystem.
* :ref:`user_space` — the applications, the C library, the shell.
* :ref:`debugging` — how to look inside all of it while it runs.

.. _so3_github: https://github.com/smartobjectoriented/so3
.. _REDS: http://www.reds.ch
.. _HEIG-VD: http://www.heig-vd.ch
.. _DRE: https://people.hes-so.ch/en/profile/3817359-daniel-rossier
