# Copyright (c) 2025-2026 EDGEMTech SA

# Class for building U-boot in infrabase

# A U-Boot built in the tree wins; otherwise fall back to the one the
# build container ships under /opt/uboot. Every consumer reads this
# variable, so the fallback reaches the FIT, the SD-card image and st.sh
# at once — and `build.sh -x uboot` transparently takes over for anyone
# working on the boot chain.

IB_UBOOT_PATH = "${@ (lambda tree: tree if os.path.isfile(os.path.join(tree, 'u-boot')) \
    or not os.path.isfile('/opt/uboot/u-boot') else '/opt/uboot')( \
    os.path.join(d.getVar('IB_DIR') or '', 'u-boot')) }"


