.. _troubleshooting:

===============
Troubleshooting
===============

The errors you are most likely to hit, what they actually mean, and what to do.
When you ask for help, say which of these you already checked — it saves everyone
time.

Read the banner first
=====================

Every front-end script prints, on startup, the tree and platform it is about to
act on:

.. code-block:: text

   [infrabase] bsp-so3  root=/home/you/sye/sye_student  platform=virt32

A surprising number of "it doesn't work" reports are a command run against the
wrong tree or the wrong platform. Read that line before anything else. When your
current directory belongs to a *different* tree than the loaded environment, the
same banner says so explicitly:

.. code-block:: text

   [infrabase] bsp-so3  WARNING: cwd is inside /home/you/sye/other but loaded env is /home/you/sye/sye_student

Environment
===========

**``build.sh: command not found``**
    ``env.sh`` was not sourced in this terminal. Source it **from the root of the
    tree** — it takes the tree's location from your current directory:

    .. code-block:: console

       $ cd ~/sye/sye_student && . ./env.sh

    Sourcing it from a subdirectory appears to work but sets the wrong root, and
    nothing on ``PATH`` will resolve. Once sourced correctly, you may ``cd``
    anywhere.

**``[infrabase] env switch required for this invocation``, then ``Continue with env.sh from … ? [y/N]``**
    You ran a script that belongs to a *different* Infrabase tree — usually
    because ``PATH`` still points at the tree you sourced last. Answer ``y`` to
    run it against its own tree for this invocation, ``n`` to abort. To make the
    switch permanent, do what the message says: ``cd <tree> && . ./env.sh``.

Container
=========

**``image 'sye-build:1.0' not found``**
    Build it: ``dbuild.sh --build``.

**``permission denied`` on ``/var/run/docker.sock``**
    Your user is not in the ``docker`` group:

    .. code-block:: console

       $ sudo usermod -aG docker $USER      # then log out and back in

**A ``virt64``, ``rpi4_64`` or ``verdin-imx8mp`` build fails on a missing compiler**
    Expected: the container is **32-bit only**. SYE runs on ``virt32`` (ARM
    32-bit, QEMU ``virt``, Cortex-A15), so the image ships only the
    ``arm-none-eabi-``, ``arm-linux-gnueabihf-`` and ``arm-linux-musleabihf-``
    toolchains — the 64-bit ones would add over 1.5 GB for nothing. Build a
    64-bit platform on the host, or add the toolchains back to
    ``docker/build-env/Dockerfile`` (its header says which ones) and pass
    ``--build-arg MUSL_TARGETS="arm-linux-musleabihf aarch64-linux-musl"``.

**``current directory is outside <tree>``**
    Only the tree is bind-mounted, and your current directory is reused verbatim
    inside the container. ``cd`` into the tree first.

**The QEMU window does not open**
    The X server is refusing the container. ``xhost +local:`` on your machine is
    usually enough. Check ``echo $DISPLAY`` is not empty; under Wayland, XWayland
    must be running. On macOS, see :ref:`container-platforms`.

Build
=====

**``sudo: a password is required`` in the middle of a build or deploy**
    Only on a **native** host, and only once: the storage steps escalate
    individual commands with ``sudo -n``, which needs a credential that survives
    into bitbake's subprocesses. Run:

    .. code-block:: console

       $ scripts/common/setup_sudo.sh

    Inside the container this never happens — it is already arranged.

**A task fails with ``No such file or directory: …/temp/fifo.NNNN``**
    Leftover from a build interrupted with ``Ctrl-C``. ``build.sh`` repairs these
    stale work directories on its next run, so simply run your build again.

**``No corresponding ITS found (…)``**
    The boot image is chosen by ``IB_TARGET_ITS:so3:<platform>`` in
    ``build/conf/local.conf``, and its value matches no ``.its`` template — a
    typo, or an ITS belonging to another platform. For the course platform it
    must be:

    .. code-block:: text

       IB_TARGET_ITS:so3:virt32 ?= "virt32_so3"

**``Refusing to re-attach <recipe> (would overwrite the files above)``**
    ``u-boot/`` and ``qemu/`` are **generated**: they are fetched from upstream
    and then patched from the recipe's patch set. Editing them directly has no
    safety net, so the build refuses to overwrite your edits rather than
    destroying them. Fold them into the patch set with ``updiff.sh <recipe>``,
    or, if you truly want them gone, ``IB_FORCE_ATTACH=1`` re-attaches and keeps
    the previous tree in ``<recipe>.back``.

    The SO3 **kernel** and **user space** are not concerned: they are committed
    in the repository, so you simply edit and rebuild them.

**The build succeeds but the change has no effect**
    Almost always a question of scope: you rebuilt a component but did not
    redeploy, or you rebuilt the wrong one. The kernel is the classic case — it
    is built *in tree*, and bitbake does not track ``so3/so3/so3.bin`` as a task
    output, so after ``build.sh -x so3`` you **must** run ``deploy.sh bsp-so3``
    to regenerate the FIT image; otherwise you boot the previous kernel. The
    mapping is in :ref:`build_system`. When in doubt, the sledgehammer is:

    .. code-block:: console

       $ build.sh -c bsp-so3 && deploy.sh bsp-so3

**Anything looks stale after a configuration change**
    The kernel keeps a ``.config`` that does not know what changed under it.
    Clean the recipe: ``build.sh -c so3``. As a last resort, ``rm -rf build/tmp``
    starts from scratch — correct, but it costs you a full rebuild. Never delete
    ``build/`` itself: it holds the layers and is tracked in git.

Deploy
======

**``sdcard.img.virt32`` does not exist, or the deploy fails immediately**
    The SD-card image is created by a separate, privileged recipe — it is not
    part of ``build.sh bsp-so3``. Run it once:

    .. code-block:: console

       $ build.sh -x filesystem

**A deploy fails right after a build was interrupted**
    ``deploy.sh`` consumes what ``build.sh`` produced; it never recompiles. Build
    again first — a deploy with no prior build fails clearly rather than silently
    rebuilding.

**A redeploy seems to change nothing**
    The storage image is still mounted from a previous run, so the deploy reuses
    that mount. Unmount and redeploy:

    .. code-block:: console

       $ umount.sh
       $ deploy.sh bsp-so3

Running
=======

**U-Boot starts, then nothing**
    The FIT image is missing or was not deployed. Check that ``so3/images/``
    holds ``virt32_so3.itb`` and that ``filesystem/sdcard.img.virt32`` exists,
    then redeploy.

**``st.sh`` exits immediately, or does nothing at all**
    Check the platform in the banner: ``st.sh`` only knows the ``virt`` machines,
    and this tree is built for ``virt32``. If ``local.conf`` says anything else,
    put it back.

**I cannot leave QEMU**
    ``Ctrl-A x``. ``Ctrl-C`` goes to the guest, not to QEMU.

Still stuck?
============

Collect, in this order: the banner line, the exact command, and the **last 30
lines** of output (``-v`` on ``build.sh`` / ``deploy.sh`` gives the full bitbake
log). A build failure without those is not something anyone can help with.
