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

# ----------------------------------------------------------
# CLEANUP + CREATE DIRS
# ----------------------------------------------------------
rm -rf "$WORKDIR"
mkdir -p "$ISO_DIR" "$OUTDIR" "$BOOT_DIR" "$GRUB_DIR" "$EFI_DIR"

THEME_DIR="$GRUB_DIR/theme"
mkdir -p "$THEME_DIR"

cp "$BG_IMG" "$THEME_DIR/background.png"

# ----------------------------------------------------------
# MAKE ROOTFS SQUASHFS
# ----------------------------------------------------------
clear
echo "================================================================"
echo "===== Neonatox Live Boot - v0.4 Carlos Sanchez - 2007-2026 ====="
echo "================================================================"

EXCLUDES="
/opt/*
/proc
/sys
/dev
/run
/tmp
/media/*
/mnt/*
/lost+found
/swapfile
/var/log/*
/var/cache/*
/var/tmp/*
/home/*/.cache/*
/home/*/.local/share/Trash/*
/home/*/.mozilla/*/cache2/*
/usr/src/*
"

echo "[*] Creating squashfs rootfs..." 
mksquashfs / "$SQUASHFS" \
    -e $(echo $EXCLUDES) \
    -comp xz -noappend
echo "[OK] Squashfs rootfs created"    

echo "[*] generating rootfs checksum..."
ROOTFS_HASH_FILE="$WORKDIR/rootfs.sha256"
sha256sum "$SQUASHFS" | awk '{print $1}' > "$ROOTFS_HASH_FILE"
echo "[OK] rootfs checksum generated"


# ----------------------------------------------------------
# CHOOSE KERNEL
# ----------------------------------------------------------
echo "[*] Searching kernel..."
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

cp "$VMLINUX" "$BOOT_DIR/vmlinuz"

FULLVER=$(uname -r)
echo "[OK] Kernel version: $FULLVER"

# ----------------------------------------------------------
# INITRAMFS BUILD
# ----------------------------------------------------------
echo "[*] Building initramfs..."
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
"

for d in $REQ_DIRS; do
    if [ -d "$MODDIR/$d" ]; then
        mkdir -p "$DEST/$d"
        cp -a "$MODDIR/$d" "$DEST/${d%/*}/"
    fi
done

# Módulos individuales críticos (asegurar inclusión explícita)
NEEDED_MODULES="
kernel/drivers/block/loop.ko*
kernel/drivers/scsi/sd_mod.ko*
kernel/drivers/scsi/sr_mod.ko*
kernel/drivers/cdrom/cdrom.ko*
kernel/drivers/usb/storage/usb-storage.ko*
kernel/drivers/ata/ahci.ko*
kernel/fs/squashfs/squashfs.ko*
kernel/fs/overlayfs/overlay.ko*
kernel/drivers/hid/hid.ko*
kernel/drivers/hid/hid-generic.ko*
kernel/drivers/hid/usbhid/usbhid.ko*
kernel/drivers/input/serio/i8042.ko*
kernel/drivers/input/keyboard/atkbd.ko*
kernel/drivers/input/serio/libps2.ko*
"

for m in $NEEDED_MODULES; do
    if [ -f "$MODDIR/$m" ]; then
        install -D "$MODDIR/$m" "$DEST/$m"
    fi
done

echo "[*] decompressing kernel modules (initramfs)"
find "$INITRAMFS/lib/modules" -name "*.ko.zst" -exec unzstd -f --rm {} \; 2>/dev/null

# Metadatos de módulos
cp "$MODDIR/modules.order"   "$DEST/" 2>/dev/null || true
cp "$MODDIR/modules.builtin" "$DEST/" 2>/dev/null || true

# Generar dependencias
depmod -b "$INITRAMFS" "$FULLVER" 2>/dev/null

install -m 0755 "$SCRIPT_DIR/initramfs/init" "$INITRAMFS/init"
install -m 0644 "$ROOTFS_HASH_FILE" "$INITRAMFS/rootfs.sha256"

echo "[*] Packing initramfs..."
( cd "$INITRAMFS" && find . -print0 | cpio --null -o -H newc | gzip -9 ) > "$INITRAMFS_IMG" 2>/dev/null
echo "[OK] initramfs ready..."


# ----------------------------------------------------------
# GRUB CONFIG
# ----------------------------------------------------------
echo "[*] Generating GRUB config..."
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
    linux /boot/vmlinuz quiet
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME} ${VERSION} live (DEBUG)" {
    linux /boot/vmlinuz debug=1 loglevel=7
    initrd /boot/initramfs.img
}
    
}
EOF
echo "[OK] GRUB config ready"

# ----------------------------------------------------------
# EFI STANDALONE
# ----------------------------------------------------------
echo "[*] building UEFI bootloader..."
grub-mkstandalone \
  -O x86_64-efi \
  -d /usr/lib/grub/x86_64-efi \
  -o "$EFI_DIR/BOOTX64.EFI" \
  "boot/grub/grub.cfg=$GRUB_DIR/grub.cfg"

echo "[OK] UEFI bootloader ready"
# ----------------------------------------------------------
# BIOS ENTRY
# ----------------------------------------------------------
echo "[*] Building BIOS bootloader..."
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

echo "[OK] BIOS bootloader ready"
# ----------------------------------------------------------
# FINAL ISO BUILD
# ----------------------------------------------------------
echo "[*] Building final ISO..."

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
echo "ISO READY:"
echo "$OUTDIR/${ISO_NAME}-${VERSION}-${ARCH}.iso"
echo "============================================"
