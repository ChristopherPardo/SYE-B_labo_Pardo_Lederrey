.. _running:

=======
Running
=======

Once ``deploy.sh`` has produced a bootable image, one script starts it:
``st.sh``. It reads the platform from ``build/conf/local.conf`` and sets up the
emulator, machine and CPU by itself — you normally pass it nothing at all.

.. code-block:: console

   $ dbuild.sh st.sh          # or just st.sh, from a container shell

QEMU
====

.. list-table::
   :header-rows: 1
   :widths: 22 78

   * - Command
     - What you get
   * - ``st.sh``
     - Headless: the guest's serial console on your terminal. The default.
   * - ``st.sh -d``
     - Also opens the **QEMU window** showing the guest's graphical screen
       (the PL111 display controller).
   * - ``st.sh -S``
     - Freeze the machine at reset and wait for a debugger (see below). Any
       option ``st.sh`` does not recognise is forwarded to QEMU.
   * - ``st.sh -h``
     - Help.

Leave QEMU with ``Ctrl-A x``. ``Ctrl-C`` goes to the **guest**, not to QEMU: it
interrupts the foreground application or cancels the current shell line.

What it starts, concretely: ``qemu-system-arm``, machine ``virt``, CPU
Cortex-A15, 4 cores, 1 GB of RAM. That QEMU is the **patched** emulator built by
the ``qemu`` recipe — the stock ``virt`` machine has no display or input devices
and the patch adds them. It boots ``u-boot/u-boot`` and presents
``filesystem/sdcard.img.virt32`` to the guest as a virtio block device — the
same image you would write to an SD card.

The graphical mode
==================

``st.sh -d`` opens a GTK window on the guest's framebuffer — an ARM **PL111**
display controller at 1024×768, 32 bpp, reachable from an application through
``/dev/fb``. The same patch adds a **PL050** PS/2 keyboard (``/dev/keyboard``)
and an absolute pointer (``/dev/mouse``), so the LVGL demos and the graphical
applications in ``so3/usr/src/`` have real input.

The serial console keeps working in your terminal while the window is open —
that is where the kernel talks to you.

Networking
==========

The stock ``virt`` machine has no Ethernet controller SO3 can drive — only
virtio-net, for which there is no driver — so the same patch that adds the
display adds an **SMSC LAN9118** MAC at ``0x08804000`` on SPI 15, which is the
``ethernet@08804000`` node of ``so3/so3/dts/virt32.dts``. The kernel side is
``devices/net/smc911x_lwip.c``, feeding the **lwIP** stack under ``net/lwip/``;
both are enabled by ``CONFIG_NET`` and ``CONFIG_SMC911X``, on in
``virt32_defconfig`` and ``virt32_fb_defconfig``.

``st.sh`` puts that NIC on QEMU's user-mode (**slirp**) stack, so no ``tap``
device and no ``sudo`` are involved: QEMU itself plays DHCP, DNS and NAT.

.. list-table::
   :header-rows: 1
   :widths: 22 78

   * - Address
     - Role
   * - ``10.0.2.15``
     - The guest, handed out by QEMU's DHCP while the driver comes up.
   * - ``10.0.2.2``
     - The gateway, which is also your host machine.
   * - ``10.0.2.3``
     - The DNS server QEMU answers on.

The trade-off is that the guest is NAT'd and not visible on the LAN. The
interface announces itself on the console shortly after boot, and ``ping``
exercises the stack end to end:

.. code-block:: text

   smc911x: detected LAN9118 controller
   IP Network up and running with address 10.0.2.15
   / % ping -c 3 10.0.2.2
   64 bytes from 10.0.2.2: icmp_seq=1 ttl=255 time=4.421875 ms

Pinging *past* the gateway needs your host to let QEMU open ICMP sockets,
otherwise slirp emulates the echo over UDP and relays back the port-unreachable
it gets. That is what ``net.ipv4.ping_group_range`` controls, and several
distributions ship it as the empty range ``1 0``; widening it with ``sudo sysctl
-w net.ipv4.ping_group_range="0 2147483647"`` lets slirp forward the echo for
real. Nothing in SO3 is involved either way.

Debugging
=========

``st.sh`` always exposes a GDB stub, and prints its port on startup:

.. code-block:: text

   GDB port:  1234

To catch something that happens before you can type, freeze the machine at reset
with QEMU's ``-S``, then attach from a second terminal:

.. code-block:: console

   $ dbuild.sh st.sh -S

The full workflow — which ELF carries the symbols, the breakpoints worth
knowing, reading a fault, and the VSCode launch configurations — is in
:ref:`debugging`.

.. tip::

   For the smallest possible turnaround, ``makeso3.sh -u`` rebuilds and
   deploys only the user space — you do not have to rebuild the kernel after
   fixing an application. ``-k`` does the mirror image. The full mapping is in
   :ref:`build_system`.
