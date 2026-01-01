#!/bin/bash
set -e

# ==========================================================
# Neonatox Live Boot Builder - your distro to bootable iso
# BIOS + UEFI + GRUB
# ==========================================================

PATH=/sbin:/bin

ISO_NAME="neonatox"
VERSION="2026"
ARCH="$(uname -m)"
LABEL="NEONATOX_LIVE"

FULLVER="$(uname -r)"
KBASE="$(echo "$FULLVER" | cut -d. -f1,2)"

VMLINUX=""

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORKDIR="/tmp/neonatox-live"
ISO_DIR="$WORKDIR/iso"
OUTDIR="$SCRIPT_DIR/output"
INITRAMFS_STAGING="$WORKDIR/initramfs"

BOOT_DIR="$ISO_DIR/boot"
GRUB_DIR="$BOOT_DIR/grub"
EFI_DIR="$ISO_DIR/EFI/BOOT"

SQUASHFS="$ISO_DIR/rootfs.squashfs"
INITRAMFS_IMG="$BOOT_DIR/initramfs.img"
BG_IMG="$SCRIPT_DIR/iso/background.png"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----------------------------------------------------------
# ERROR HANDLING (section-aware)
# ----------------------------------------------------------
CURRENT_SECTION="initialization"

trap 'echo -e "${RED}[FATAL]${NC} error in section: $CURRENT_SECTION (line $LINENO)"; echo "Command: $BASH_COMMAND"; exit 99' ERR

# ----------------------------------------------------------
# PRE-CHECKS
# ----------------------------------------------------------
CURRENT_SECTION="pre-checks"

echo -e "${YELLOW}[CHECK]${NC} validating environment..."


REQUIRED_BINS="
mksquashfs
xorriso
grub-mkimage
grub-mkstandalone
cpio
xz
sha256sum
depmod
modprobe
mknod
realpath
unxz
gunzip
unzstd
"

for bin in $REQUIRED_BINS; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} missing required binary: $bin"
        exit 10
    fi
done

REQUIRED_DIRS="
/boot
/usr/lib/grub
/lib/modules
"

for dir in $REQUIRED_DIRS; do
    if [ ! -d "$dir" ]; then
        echo -e "${RED}[ERROR]${NC} missing required directory: $dir"
        exit 11
    fi
done

[ -f "$BG_IMG" ] || {
    echo -e "${RED}[ERROR]${NC} background image not found: $BG_IMG"
    exit 12
}

echo -e "${GREEN}[OK]${NC} environment valid"

# ----------------------------------------------------------
# CLEANUP + CREATE DIRS
# ----------------------------------------------------------
CURRENT_SECTION="cleanup and directory setup"

rm -rf "$WORKDIR"
mkdir -p "$ISO_DIR" "$OUTDIR" "$BOOT_DIR" "$GRUB_DIR" "$EFI_DIR"

THEME_DIR="$GRUB_DIR/theme"
mkdir -p "$THEME_DIR"

cp "$BG_IMG" "$THEME_DIR/background.png"

# ----------------------------------------------------------
# MAKE ROOTFS SQUASHFS
# ----------------------------------------------------------
CURRENT_SECTION="rootfs squashfs"

clear
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}=====${NC} ${GREEN}Neonatox Live Boot - v0.5 Carlos Sanchez - 2007-2026 ${YELLOW}=====${NC}"
echo -e "${YELLOW}================================================================${NC}"


EXCLUDES="
/boot/*
/opt/*
/proc
/sys
/dev
/run
/tmp
/media/*/*
/mnt/*
/lost+found
/swapfile
/var/log/*
/var/cache/*
/var/tmp/*
/home/*
/usr/src/*
/usr/lib/firmware/*
"

echo -e "${YELLOW}[INFO]${NC} Creating squashfs rootfs..." 
mksquashfs / "$SQUASHFS"  -e $(echo $EXCLUDES) -comp xz -b 1024K -Xbcj x86 -always-use-fragments -keep-as-directory
echo -e "${GREEN}[OK]${NC} Squashfs rootfs created"    

echo -e "${YELLOW}[INFO]${NC} generating rootfs checksum..."
ROOTFS_HASH_FILE="$WORKDIR/rootfs.sha256"

CURRENT_SECTION="rootfs checksum"
sha256sum "$SQUASHFS" | awk '{print $1}' > "$ROOTFS_HASH_FILE"
echo -e "${GREEN}[OK]${NC} rootfs checksum generated"


# ----------------------------------------------------------
# CHOOSE KERNEL
# ----------------------------------------------------------
CURRENT_SECTION="kernel selection"

echo -e "${YELLOW}[INFO]${NC} Searching kernel..."
KLIST=$(ls /boot/vmlinuz-* 2>/dev/null | grep "$KBASE" | sort || true)

if [ -z "$KLIST" ]; then
    echo "[ERROR] kernel not found"
    exit 1
fi

COUNT=$(echo "$KLIST" | wc -l)

if [ "$COUNT" -eq 1 ]; then
    VMLINUX="$KLIST"
else
    echo "MULTIPLE kernels found:"
    i=1
    for k in $KLIST; do
        echo "  $i) $k"
        eval KPATH_$i="$k"
        i=$((i+1))
    done
    read -rp "Select kernel number: " SEL
    eval SELECTED=\$KPATH_"$SEL"
    [ -z "$SELECTED" ] && exit 1
    VMLINUX="$SELECTED"
fi

CURRENT_SECTION="kernel copy"

[ -f "$VMLINUX" ] || {
    echo -e "${RED}[ERROR]${NC} kernel image not found: $VMLINUX"
    exit 20
}

cp "$VMLINUX" "$BOOT_DIR/vmlinuz"


FULLVER=$(uname -r)
echo -e "${GREEN}[OK]${NC} Kernel version: $FULLVER"

# ----------------------------------------------------------
# INITRAMFS BUILD
# ----------------------------------------------------------
CURRENT_SECTION="initramfs build"

echo -e "${YELLOW}[INFO]${NC} Building initramfs..."
INITRAMFS="$WORKDIR/initramfs"
mkdir -p "$INITRAMFS"

mkdir -p \
  "$INITRAMFS/bin" \
  "$INITRAMFS/sbin" \
  "$INITRAMFS/etc" \
  "$INITRAMFS/dev" \
  "$INITRAMFS/proc" \
  "$INITRAMFS/sys" \
  "$INITRAMFS/run" \
  "$INITRAMFS/tmp" \
  "$INITRAMFS/mnt/iso" \
  "$INITRAMFS/mnt/iso_test" \
  "$INITRAMFS/mnt/newroot" \
  "$INITRAMFS/mnt/ro_root" \
  "$INITRAMFS/lib/modules/$FULLVER"
  

CURRENT_SECTION="initramfs busybox setup"

install -m 0755 "$SCRIPT_DIR/initramfs/busybox" "$INITRAMFS/bin/busybox"

(
  cd "$INITRAMFS/bin"
  ./busybox --list | grep -v "init" | grep -v "poweroff" | grep -v "reboot" | while read app; do
    [ "$app" = "busybox" ] && continue
    ln -sf busybox "$app"
  done
  
)
ln -sf ../bin/busybox "$INITRAMFS/sbin/switch_root"

# Reboot via kernel (emergency shell)
cat > "$INITRAMFS/sbin/reboot" << "EOF"
#!/bin/sh

echo "Restarting..."
sleep 1
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
sync
echo b > /proc/sysrq-trigger
EOF

# Power off via kernel (emergency shell)
cat > "$INITRAMFS/sbin/poweroff" << "EOF"
#!/bin/sh

echo "Shutting down..."
sleep 1
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
sync
echo o > /proc/sysrq-trigger
EOF

chmod 0755 $INITRAMFS/sbin/{reboot,poweroff}

# Nodos de dispositivo mínimos
mknod -m 600 "$INITRAMFS/dev/console" c 5 1
mknod -m 666 "$INITRAMFS/dev/null"    c 1 3
mknod -m 666 "$INITRAMFS/dev/zero"    c 1 5
mknod -m 666 "$INITRAMFS/dev/tty"     c 5 0
mknod -m 622 "$INITRAMFS/dev/tty1"    c 4 1
mknod -m 622 "$INITRAMFS/dev/tty2"    c 4 2
mknod -m 622 "$INITRAMFS/dev/tty3"    c 4 3
mknod -m 622 "$INITRAMFS/dev/tty4"    c 4 4

# ---------------------------------------------
# Copiar módulos del kernel
# ---------------------------------------------
MODDIR="/lib/modules/$FULLVER"
DEST="$INITRAMFS/lib/modules/$FULLVER"
mkdir -p "$DEST"

# Directorios generales necesarios
REQ_DIRS="
kernel/drivers/block
kernel/drivers/scsi
kernel/drivers/usb
kernel/drivers/ata
kernel/drivers/cdrom/
kernel/fs
kernel/drivers/hid
kernel/drivers/input
kernel/lib/lz4
kernel/lib/842
"

CURRENT_SECTION="initramfs kernel modules copy"

for d in $REQ_DIRS; do
    if [ -d "$MODDIR/$d" ]; then
        mkdir -p "$DEST/$d"
        cp -a "$MODDIR/$d" "$DEST/${d%/*}/"
    fi
done

echo -e "${YELLOW}[INFO]${NC} decompressing kernel modules (on initramfs)"
# Unzip .ko.zst files if they exist
find "$INITRAMFS/lib/modules" -name "*.ko.zst" -exec unzstd -f --rm {} \; 2>/dev/null || true
# Unzip .ko.gz files with gunzip if they exist
find "$INITRAMFS/lib/modules" -name "*.ko.gz" -exec gunzip -f {} \; 2>/dev/null || true
# Unzip .ko.xz files with unxz if they exist
find "$INITRAMFS/lib/modules" -name "*.ko.xz" -exec unxz -f {} \; 2>/dev/null || true

# Metadatos de módulos
cp "$MODDIR/modules.order"   "$DEST/" 2>/dev/null || true
cp "$MODDIR/modules.builtin" "$DEST/" 2>/dev/null || true

# Generar dependencias
CURRENT_SECTION="initramfs depmod"

depmod -b "$INITRAMFS" "$FULLVER" 2>/dev/null || true

install -m 0755 "$SCRIPT_DIR/initramfs/init" "$INITRAMFS/init"
install -m 0755 "$SCRIPT_DIR/initramfs/live-config.sh" "$INITRAMFS/live-config.sh"
install -m 0644 "$ROOTFS_HASH_FILE" "$INITRAMFS/rootfs.sha256"


CURRENT_SECTION="initramfs packing"

echo -e "${YELLOW}[INFO]${NC} Packing initramfs..."
( cd "$INITRAMFS" && find . -print | cpio -o -H newc 2>/dev/null | xz -T0 -f --extreme --check=crc32 ) > "$INITRAMFS_IMG" 2>/dev/null
echo -e "${GREEN}[OK]${NC} initramfs ready..."


# ----------------------------------------------------------
# GRUB CONFIG
# ----------------------------------------------------------
CURRENT_SECTION="grub configuration"

echo -e "${YELLOW}[INFO]${NC} Generating GRUB config..."
cp /usr/share/grub/unicode.pf2 "$GRUB_DIR/font.pf2" 2>/dev/null \
    || cp /usr/share/grub/*/unicode.pf2 "$GRUB_DIR/font.pf2"

cat > "$GRUB_DIR/grub.cfg" <<EOF
set default=0
set timeout=15

# Configurar resolución de pantalla
set gfxmode=1024x768,800x600,auto
set gfxpayload=keep

insmod all_video
insmod gfxterm
insmod png
insmod vbe
insmod video_bochs
insmod video_cirrus

loadfont /boot/grub/font.pf2
terminal_output gfxterm

background_image /boot/grub/theme/background.png

menuentry "${ISO_NAME} ${VERSION} live" {
    linux /boot/vmlinuz quiet loglevel=3
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME} ${VERSION} live (Language & Live User Config)" {
    linux /boot/vmlinuz quiet neoconfig=1
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME} ${VERSION} live (Failsafe graphics)" {
    linux /boot/vmlinuz quiet nomodeset vga=normal
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME} ${VERSION} live (DEBUG)" {
    linux /boot/vmlinuz debug=1 loglevel=7
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME} ${VERSION} live (Initramfs debug)" {
    linux /boot/vmlinuz initrd_debug=1
    initrd /boot/initramfs.img
}

EOF
echo -e "${GREEN}[OK]${NC} GRUB config ready"

# ----------------------------------------------------------
# EFI STANDALONE
# ----------------------------------------------------------
CURRENT_SECTION="grub efi build"

echo -e "${YELLOW}[INFO]${NC} building UEFI bootloader..."
grub-mkstandalone \
  -O x86_64-efi \
  -d /usr/lib/grub/x86_64-efi \
  -o "$EFI_DIR/BOOTX64.EFI" \
  "boot/grub/grub.cfg=$GRUB_DIR/grub.cfg"

echo -e "${GREEN}[OK]${NC} UEFI bootloader ready"
# ----------------------------------------------------------
# BIOS ENTRY
# ----------------------------------------------------------
CURRENT_SECTION="grub bios build"

echo -e "${YELLOW}[INFO]${NC} Building BIOS bootloader..."
mkdir -p "$GRUB_DIR/i386-pc"

cp -r /usr/lib/grub/i386-pc/* "$GRUB_DIR/i386-pc/" 2>/dev/null

grub-mkimage \
  -O i386-pc \
  -d /usr/lib/grub/i386-pc \
  -p /boot/grub \
  -o "$GRUB_DIR/i386-pc/core.img" \
  biosdisk iso9660 part_msdos normal search search_label configfile

cat \
  /usr/lib/grub/i386-pc/cdboot.img \
  "$GRUB_DIR/i386-pc/core.img" \
    > "$GRUB_DIR/i386-pc/eltorito.img"

echo -e "${GREEN}[OK]${NC} BIOS bootloader ready"
# ----------------------------------------------------------
# FINAL ISO BUILD
# ----------------------------------------------------------
CURRENT_SECTION="final iso build"

echo -e "${YELLOW}[INFO]${NC} Building final ISO..."

xorriso -as mkisofs \
  -iso-level 3 \
  -o "$OUTDIR/${ISO_NAME}-${VERSION}-${ARCH}.iso" \
  -V "$LABEL" \
  -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-catalog boot/grub/i386-pc/boot.cat \
  -eltorito-alt-boot \
     -e EFI/BOOT/BOOTX64.EFI \
     -no-emul-boot \
  "$ISO_DIR"

echo "============================================"
echo -e "${YELLOW}ISO READY${NC}:"
echo -e "${GREEN}$OUTDIR/${ISO_NAME}-${VERSION}-${ARCH}.iso${NC}"
echo "============================================"
