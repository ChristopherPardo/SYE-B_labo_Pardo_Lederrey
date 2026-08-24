#!/usr/bin/env python3
# Generator for source/img/so3.drawio and the exported PNGs.
#
# The .drawio file is the editable source of truth; this script lets us
# regenerate it from a compact description. After editing, export the PNGs
# with the helper at the bottom of this file (see README in doc/).
#
#   python3 gen_so3_diagrams.py            # (re)generate so3.drawio
#   ./export_png.sh                        # render every page to PNG
#
# The SYE documentation keeps six diagrams, all ARM 32-bit standalone. The
# diagrams that only make sense for the other configurations (AVZ domains, SO3
# capsules) and the ones this course does not need (device model, display/input
# path) live upstream, with the documentation they illustrate:
# https://smartobjectoriented.github.io/so3
#
import html

# ---- palette -------------------------------------------------------------
KERNEL = "fillColor=#dae8fc;strokeColor=#6c8ebf;"
USER   = "fillColor=#d5e8d4;strokeColor=#82b366;"
AVZ    = "fillColor=#ffe6cc;strokeColor=#d79b00;"
CAPS   = "fillColor=#fff2cc;strokeColor=#d6b656;"
HW     = "fillColor=#f8cecc;strokeColor=#b85450;"
NEUTRAL= "fillColor=#f5f5f5;strokeColor=#999999;"
WHITE  = "fillColor=#ffffff;strokeColor=#666666;"
NONE   = "fillColor=none;strokeColor=#444444;dashed=1;"

BOX = "rounded=1;whiteSpace=wrap;html=1;arcSize=8;"
CONT= "rounded=1;whiteSpace=wrap;html=1;arcSize=4;verticalAlign=top;fontStyle=1;"
NOTE= "shape=note;whiteSpace=wrap;html=1;size=14;"
ARR = ("edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;"
       "strokeColor=#444444;fontSize=10;")
ARR_D = ARR + "dashed=1;"


class Page:
    def __init__(self, name):
        self.name = name
        self.cells = []
        self.n = 1

    def _id(self):
        self.n += 1
        return f"c{self.n}"

    @staticmethod
    def _v(label):
        # drawio renders \n only when encoded as a numeric char-ref
        return html.escape(label).replace("\n", "&#10;")

    def box(self, x, y, w, h, label, style=BOX, fontsize=12, fontstyle=0):
        i = self._id()
        s = f"{style}fontSize={fontsize};"
        if fontstyle:
            s += f"fontStyle={fontstyle};"
        self.cells.append(
            f'<mxCell id="{i}" value="{self._v(label)}" style="{s}" '
            f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" '
            f'height="{h}" as="geometry"/></mxCell>')
        return i

    def label(self, x, y, w, h, text, fontsize=11, bold=False):
        st = ("text;html=1;whiteSpace=wrap;align=center;verticalAlign=middle;"
              f"fontSize={fontsize};{'fontStyle=1;' if bold else ''}")
        i = self._id()
        self.cells.append(
            f'<mxCell id="{i}" value="{self._v(text)}" style="{st}" '
            f'vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{w}" '
            f'height="{h}" as="geometry"/></mxCell>')
        return i

    def edge(self, src, dst, label="", style=ARR):
        i = self._id()
        self.cells.append(
            f'<mxCell id="{i}" value="{html.escape(label)}" style="{style}" '
            f'edge="1" parent="1" source="{src}" target="{dst}">'
            f'<mxGeometry relative="1" as="geometry"/></mxCell>')
        return i

    def xml(self):
        body = "".join(self.cells)
        return (f'<diagram name="{html.escape(self.name)}" id="{self.name}">'
                f'<mxGraphModel dx="1000" dy="700" grid="0" gridSize="10" '
                f'guides="1" tooltips="1" connect="1" arrows="1" fold="1" '
                f'page="1" pageScale="1" pageWidth="1100" pageHeight="800" '
                f'math="0" shadow="0"><root>'
                f'<mxCell id="0"/><mxCell id="1" parent="0"/>{body}'
                f'</root></mxGraphModel></diagram>')


pages = []

# =========================================================================
# 1. System architecture
# =========================================================================
p = Page("architecture")
p.label(0, 10, 1080, 30, "SO3 system architecture", 16, True)
p.box(40, 60, 1000, 120, "User space  —  unprivileged (USR mode)", CONT, 13, 1)
for i, lbl in enumerate(["init.elf", "sh.elf", "ls / cat /\nmore / echo",
                         "threads /\npipes", "graphical\ndemos"]):
    p.box(70 + i*195, 100, 175, 60, lbl, USER, 10)
p.box(40, 210, 1000, 300, "Kernel space  —  privileged (SVC mode)", CONT, 13, 1)
p.box(70, 250, 940, 40, "System call interface   (svc  →  syscall_interrupt  →  syscall_table)", NEUTRAL, 11)
subs = [
    ("Processes &\nthreads", "kernel/ — pcb, tcb,\nscheduler"),
    ("Memory", "mm/ — frame table,\nheap, MMU"),
    ("Filesystem", "fs/ — VFS, FAT,\ndevfs, ELF loader"),
    ("IPC", "ipc/ — signals,\npipes, semaphores"),
]
for i, (t, d) in enumerate(subs):
    p.box(70 + i*237, 310, 220, 80, f"{t}\n\n{d}", KERNEL, 10)
p.box(70, 410, 940, 80, "Device drivers   (devices/)\n"
      "interrupt controller · timer · serial (UART) · framebuffer · keyboard / mouse · RAM disk",
      KERNEL, 10)
p.box(40, 540, 1000, 60, "Hardware  —  QEMU virt, ARM 32-bit (Cortex-A15), described by a device tree", HW, 12)
pages.append(p)

# =========================================================================
# 2. Processor modes
# =========================================================================
p = Page("modes")
p.label(0, 10, 1080, 30, "ARMv7 processor modes — where SO3 runs", 16, True)
p.box(60, 70, 520, 430, "Normal operation", CONT, 13, 1)
usr = p.box(110, 125, 420, 70, "USR — user applications\nunprivileged: no privileged instruction,\nno access to the kernel's memory", USER, 11)
svc = p.box(110, 250, 420, 70, "SVC — the SO3 kernel\nthe boot path, and every system call", KERNEL, 11)
hw  = p.box(110, 400, 420, 55, "Hardware", HW, 11)
p.edge(usr, svc, "svc   (system call)", ARR + "exitX=0.25;exitY=1;entryX=0.25;entryY=0;")
p.edge(svc, usr, "return", ARR + "exitX=0.75;exitY=0;entryX=0.75;entryY=1;")
p.box(640, 70, 400, 430, "Exception modes", CONT, 13, 1)
p.box(680, 125, 320, 55, "IRQ — hardware interrupt", KERNEL, 10)
p.box(680, 200, 320, 55, "ABT — data / prefetch abort\n(a memory fault)", KERNEL, 10)
p.box(680, 275, 320, 55, "UND — undefined instruction", KERNEL, 10)
p.box(680, 350, 320, 40, "FIQ — fast interrupt (unused)", NONE, 10)
p.label(680, 400, 320, 90, "Each has its own banked sp and lr.\nThe handler saves the interrupted\ncontext into a stack frame\n(struct cpu_regs), then runs C code.", 10)
pages.append(p)

# =========================================================================
# 3. Virtual address space
# =========================================================================
p = Page("memory")
p.label(0, 10, 1080, 30, "Virtual address space of a process (ARM 32-bit)", 16, True)
p.box(80, 70, 420, 500, "User   0x00000000 … 0xBFFFFFFF", CONT, 11, 1)
p.box(120, 120, 340, 45, "0x00000000   unmapped\n(so a NULL dereference faults)", NONE, 9)
p.box(120, 180, 340, 45, "0x00001000   initial user code\n(USER_SPACE_VADDR)", USER, 9)
p.box(120, 240, 340, 45, "ELF text / data / bss\n(loaded by execve)", USER, 9)
p.box(120, 300, 340, 40, "heap   (brk, grows up)", USER, 9)
p.box(120, 480, 340, 40, "user stack   (grows down)", USER, 9)
p.label(120, 350, 340, 120, "Private to the process.\nSwitching process swaps only\nthis half — TTBR0 is pointed at\nthe new level-1 table.", 9)
p.box(580, 70, 420, 500, "Kernel   0xC0000000 … 0xFFFFFFFF", CONT, 11, 1)
p.box(620, 120, 340, 40, "0xC0008000   vectors + .head.text", KERNEL, 9)
p.box(620, 170, 340, 40, ".text / .data / .bss", KERNEL, 9)
p.box(620, 220, 340, 40, "per-CPU data", KERNEL, 9)
p.box(620, 270, 340, 40, "system page tables", KERNEL, 9)
p.box(620, 320, 340, 40, "kernel heap   (CONFIG_HEAP_SIZE_MB)", KERNEL, 9)
p.box(620, 370, 340, 40, "kernel stacks", KERNEL, 9)
p.label(620, 420, 340, 130, "Identical in EVERY process:\npgtable_copy_kernel_area() copies\nthese entries into each new\nlevel-1 table, so the kernel stays\nmapped across a context switch.", 9)
p.label(80, 590, 920, 60, "Two-level translation: a level-1 table of 4096 entries (one per 1 MB), each either "
        "mapping a 1 MB section or pointing at a level-2 table of 256 entries (one per 4 KB page).", 10)
pages.append(p)

# =========================================================================
# 4. Boot flow
# =========================================================================
p = Page("boot")
p.label(0, 20, 1080, 30, "Boot flow — from U-Boot to the shell", 16, True)
EX = ARR + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;"
ub  = p.box(40, 90, 220, 70, "U-Boot\nloads the FIT image (.itb)\nfrom the SD-card", NEUTRAL, 10)
st  = p.box(310, 90, 220, 70, "__start   (head.S)\nMMU off, physical address", KERNEL, 10)
mmu = p.box(580, 90, 220, 70, "mmu_setup\nMMU on → jump to 0xC0000000", KERNEL, 10)
km  = p.box(850, 90, 210, 70, "__kernel_main\nearly_memory_init\nsetup_arch", KERNEL, 10)
p.edge(ub, st, "", EX); p.edge(st, mmu, "", EX); p.edge(mmu, km, "", EX)
rowA = [
    ("kernel_start()", "the C entry point"),
    ("memory_init()", "frame table\n+ page tables"),
    ("devices_init()", "device tree, timer,\nserial"),
    ("vfs_init()", "mount the root\nfilesystem"),
]
rowB = [
    ("scheduler_init()", "ready to schedule"),
    ("rest_init()", "the first kernel thread"),
    ("create_root_process()", "map 0x1000, switch\nto USR mode"),
    ("init.elf → sh.elf", "the  / %  prompt"),
]
ax = [40, 295, 550, 805]
ids_a = [p.box(ax[i], 250, 235, 80, f"{rowA[i][0]}\n{rowA[i][1]}", KERNEL, 10) for i in range(4)]
ids_b = [p.box(ax[3-i], 390, 235, 80, f"{rowB[i][0]}\n{rowB[i][1]}",
               USER if i >= 2 else KERNEL, 10) for i in range(4)]
p.edge(km, ids_a[0])
for i in range(3):
    p.edge(ids_a[i], ids_a[i+1], "", EX)
p.edge(ids_a[3], ids_b[0])
for i in range(3):
    p.edge(ids_b[i], ids_b[i+1], "",
           ARR + "exitX=0;exitY=0.5;entryX=1;entryY=0.5;")
pages.append(p)

# =========================================================================
# 5. System call path
# =========================================================================
p = Page("syscall")
p.label(0, 10, 1080, 30, "System call path (ARM 32-bit)", 16, True)
a = p.box(60, 90, 210, 80, "USR — user code\nr7 = syscall number\nr0..r5 = arguments\nsvc", USER, 10)
b = p.box(320, 90, 220, 80, "vector table (__vectors)\n“software interrupt” slot\n→ syscall_interrupt", KERNEL, 10)
c = p.box(590, 90, 230, 80, "syscall_interrupt\nsave r0-r12, SPSR,\nbanked sp/lr of USR", KERNEL, 10)
d = p.box(870, 90, 190, 80, "arch_syscall_handle()\n(ARM TLS calls)", KERNEL, 10)
e = p.box(870, 230, 190, 80, "syscall_handle()\ncheck nr < NR_SYSCALLS", KERNEL, 10)
f = p.box(590, 230, 230, 80, "syscall_table[nr]\ngenerated from\nsyscall.tbl", KERNEL, 10)
g = p.box(320, 230, 220, 80, "sys_xxx()\nSYSCALL_DEFINEn()", KERNEL, 10)
h = p.box(60, 230, 210, 80, "return value → saved r0\nrestore the frame\n→ back to USR", USER, 10)
for s, t in [(a,b),(b,c),(c,d),(d,e),(e,f),(f,g),(g,h)]:
    p.edge(s, t)
p.label(60, 350, 1000, 50, "scripts/syscall_gen.sh turns syscall.tbl and arch/arm32/syscall.h.in into "
        "generated/syscall_table.h.in and syscall_number.h, so the kernel and the MUSL libc "
        "always agree on the numbering.", 10)
pages.append(p)

# =========================================================================
# 6. Infrabase build & deploy flow
# =========================================================================
p = Page("build")
p.label(0, 10, 1080, 30, "Infrabase build & deploy flow", 16, True)
cfg = p.box(40, 60, 300, 110,
            "build/conf/local.conf\n\nIB_PLATFORM = virt32\nIB_CONFIG:so3 · IB_TARGET_ITS:so3",
            NEUTRAL, 10)
bsh = p.box(390, 78, 230, 74, "scripts/build.sh\nbsp-so3   (recipe positional)", WHITE, 11)
bb  = p.box(670, 78, 230, 74, "bitbake\nmeta-* layers + recipes", AVZ, 11)
p.edge(cfg, bsh); p.edge(bsh, bb)
rec = p.box(40, 200, 1020, 175, "Recipes (meta-* layers)", CONT, 12, 1)
p.box(70, 245, 150, 110, "so3 kernel\n(meta-so3)\n\nIN-TREE\nKconfig + dts", KERNEL, 10)
p.box(265, 245, 150, 110, "u-boot\n(meta-uboot)\n\nfetched\n+ patched", NEUTRAL, 10)
p.box(460, 245, 150, 110, "qemu\n(meta-qemu)\n\nfetched\n+ patched", NEUTRAL, 10)
p.box(655, 245, 150, 110, "usr-so3\n(meta-usr)\n\nCMake + MUSL\n(meta-toolchain)", USER, 10)
p.box(850, 245, 160, 50, "rootfs-so3\n(meta-rootfs)", USER, 9)
p.box(850, 305, 160, 50, "bsp-so3\n(meta-bsp)", CAPS, 9)
p.edge(bb, rec, "", ARR + "exitX=0.5;exitY=1;entryX=0.73;entryY=0;")
itb = p.box(70, 420, 250, 64,
            "do_itb → render + mkimage\nfiles/its/*.its  →  so3/images/*.itb", WHITE, 10)
dep = p.box(420, 420, 250, 64,
            "scripts/deploy.sh bsp-so3\n→ sdcard.img.virt32  (FAT boot + rootfs)", WHITE, 10)
run = p.box(770, 420, 270, 64,
            "scripts/st.sh  [-d]\n→ QEMU virt32 (Cortex-A15)", WHITE, 10)
p.edge(rec, itb, "", ARR + "exitX=0.15;exitY=1;entryX=0.5;entryY=0;")
p.edge(itb, dep, "", ARR + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
p.edge(dep, run, "", ARR + "exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
p.label(40, 520, 1020, 70,
        "SO3 kernel and user space are built IN-TREE (committed sources) — that is what you edit "
        "during the labs. u-boot and qemu are FETCHED and local edits are kept as patches: edit the "
        "source, then 'scripts/updiff.sh RECIPE' regenerates files/000N-*.patch (diff of S.pristine "
        "vs the working tree).", 10)
pages.append(p)

# ---- emit ----------------------------------------------------------------
out = ('<mxfile host="so3-doc" type="device">'
       + "".join(pg.xml() for pg in pages) + "</mxfile>")
with open("so3.drawio", "w") as fh:
    fh.write(out)
print(f"wrote so3.drawio with {len(pages)} page(s):")
for i, pg in enumerate(pages):
    print(f"  [{i}] {pg.name}")
