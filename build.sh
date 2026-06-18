#!/bin/bash
set -e

# ==========================================================
# Neonatox Live Boot Builder - your distro to bootable iso
# BIOS + UEFI + GRUB
# ==========================================================

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NLB_VERSION="v0.9"

# ---------------------------------------------
# Default values (safe fallback)
# ---------------------------------------------

ISO_NAME="nlb-linux-live"
VERSION="1"
ARCH="$(uname -m)"
LABEL="NLB_LINUX_LIVE"

# ---------------------------------------------
# Override only if /etc/os-release exists
# ---------------------------------------------
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release

    # Base name (lowercase, ISO filename)
    if [ -n "${ID:-}" ]; then
        BASE_NAME="$(printf '%s\n' "$ID" | tr '[:upper:]' '[:lower:]')"
    elif [ -n "${NAME:-}" ]; then
        BASE_NAME="$(printf '%s\n' "$NAME" \
            | tr '[:upper:]' '[:lower:]' \
            | tr ' ' '-' )"
    else
        BASE_NAME="linux"
    fi


    ISO_NAME="${BASE_NAME}-live"

    # Version
    if [ -n "${VERSION_ID:-}" ]; then
        VERSION="$VERSION_ID"
    fi

    # LABEL always uppercase
    LABEL="$(printf '%s_LIVE\n' "$BASE_NAME" | tr '[:lower:]' '[:upper:]')"
else
    # fallback consistency
    ISO_NAME="nlb-linux-live"
    LABEL="NLB_LINUX_LIVE"
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)

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
# ARGUMENT PARSER
# ----------------------------------------------------------

NETINSTALL_MODE=false
WITHOUT_MAKE_ISO=false
MAKE_ISO_ONLY=false
DO_CLEAN=false
DO_CLEAN_ALL=false

show_help() {
    cat <<EOF
Uso: sudo ./build.sh [OPCIONES]

Opciones:
  --make-netinstall        Generar ISO netinstall (sin squashfs, con herramientas de red)
  --without-make-iso       Preparar artefactos sin empaquetar la ISO
  --make-iso               Solo empaquetar ISO desde artefactos existentes
  --clean                  Limpiar directorio de trabajo
  --clean-all              Limpiar workdir, fuentes de tools e ISOs generadas
  --version                Muestra la version
  --help, -h               Mostrar esta ayuda

Sin argumentos: build completo + ISO live (comportamiento actual)
EOF
}

show_ver(){
echo "Neonatox Live Boot - ${NLB_VERSION} Carlos Sanchez - 2007-2026"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --make-netinstall) NETINSTALL_MODE=true ;;
        --without-make-iso) WITHOUT_MAKE_ISO=true ;;
        --make-iso) MAKE_ISO_ONLY=true ;;
        --clean) DO_CLEAN=true ;;
        --clean-all) DO_CLEAN_ALL=true ;;
        --version|-v) show_ver; exit 0 ;;
        --help|-h) show_help; exit 0 ;;
        *) echo -e "${RED}[ERROR]${NC} Argumento desconocido: $1" >&2; show_help; exit 1 ;;
    esac
    shift
done

# Validaciones entre flags
if [ "$MAKE_ISO_ONLY" = true ] && [ "$WITHOUT_MAKE_ISO" = true ]; then
    echo -e "${RED}[ERROR]${NC} --make-iso y --without-make-iso son contradictorios" >&2
    exit 1
fi

# --clean y --clean-all tienen prioridad y salen
if [ "$DO_CLEAN" = true ] || [ "$DO_CLEAN_ALL" = true ]; then
    echo -e "${YELLOW}[CLEAN]${NC} Limpiando workdir..."
    rm -rf "$WORKDIR"
    if [ "$DO_CLEAN_ALL" = true ]; then
        echo -e "${YELLOW}[CLEAN]${NC} Limpiando fuentes de tools..."
        rm -rf "$SCRIPT_DIR"/tools/*/ "$SCRIPT_DIR"/tools/*.tar.* 2>/dev/null || true
        echo -e "${YELLOW}[CLEAN]${NC} Limpiando ISOs generadas..."
        rm -f "$OUTDIR"/*.iso 2>/dev/null || true
    fi
    echo -e "${GREEN}[OK]${NC} Limpieza completada"
    exit 0
fi

# --make-netinstall: ajustar modo
if [ "$NETINSTALL_MODE" = true ]; then
    echo -e "${YELLOW}[INFO]${NC} Modo netinstall activado"
fi

# ----------------------------------------------------------
# PRE-CHECKS
# ----------------------------------------------------------
CURRENT_SECTION="pre-checks"

echo -e "${YELLOW}[CHECK]${NC} validating environment..."

# Binarios siempre requeridos
REQUIRED_BINS="
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
initramfs/busybox
"

# mksquashfs no necesario en modo netinstall
if [ "$NETINSTALL_MODE" = false ]; then
    REQUIRED_BINS="$REQUIRED_BINS
mksquashfs"
fi

# xorriso no necesario solo con --without-make-iso
if [ "$WITHOUT_MAKE_ISO" = false ]; then
    REQUIRED_BINS="$REQUIRED_BINS
xorriso"
fi

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
    if [ "$MAKE_ISO_ONLY" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} background image not found (not needed for --make-iso)"
    else
        echo -e "${RED}[ERROR]${NC} background image not found: $BG_IMG"
        exit 12
    fi
}

echo -e "${GREEN}[OK]${NC} environment valid"

# ----------------------------------------------------------
# MAKE ISO ONLY (skip build, repackage from existing artifacts)
# ----------------------------------------------------------
if [ "$MAKE_ISO_ONLY" = true ]; then
    echo -e "${YELLOW}[INFO]${NC} Modo solo empaquetado ISO"
    for f in "$SQUASHFS" "$INITRAMFS_IMG" "$GRUB_DIR/grub.cfg" "$GRUB_DIR/i386-pc/eltorito.img" "$EFI_DIR/BOOTX64.EFI"; do
        if [ ! -f "$f" ]; then
            echo -e "${RED}[ERROR]${NC} Artefacto faltante: $f" >&2
            echo -e "${RED}[ERROR]${NC} Ejecute ./build.sh --without-make-iso primero" >&2
            exit 1
        fi
    done

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
    exit 0
fi

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
if [ "$NETINSTALL_MODE" = false ]; then
CURRENT_SECTION="rootfs squashfs"

clear
echo -e "${YELLOW}========${NC} ${GREEN}Neonatox Live Boot - ${NLB_VERSION} Carlos Sanchez - 2007-2026 ${YELLOW}========${NC}"
echo -e "${YELLOW}==========${NC} https://github.com/cargabsj175/neonatox-live-boot ${YELLOW}=========${NC}"

EXCLUDES_FILE="$SCRIPT_DIR/EXCLUDES"

if [ ! -f "$EXCLUDES_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} excludes file not found: $EXCLUDES_FILE"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Using excludes from $EXCLUDES_FILE"

echo -e "${YELLOW}[INFO]${NC} Creating squashfs rootfs..." 
mksquashfs / "$SQUASHFS" -e $(grep -v '^\s*$' "$EXCLUDES_FILE") -comp xz -b 1024K -Xbcj x86 -always-use-fragments -keep-as-directory
echo -e "${GREEN}[OK]${NC} Squashfs rootfs created"    

echo -e "${YELLOW}[INFO]${NC} generating rootfs checksum..."
ROOTFS_HASH_FILE="$ISO_DIR/rootfs.sha256"

CURRENT_SECTION="rootfs checksum"
sha256sum "$SQUASHFS" | awk '{print $1}' > "$ROOTFS_HASH_FILE"
echo -e "${GREEN}[OK]${NC} rootfs checksum generated"
fi

# ----------------------------------------------------------
# CHOOSE KERNEL
# ----------------------------------------------------------
CURRENT_SECTION="kernel selection"

echo -e "${YELLOW}[INFO]${NC} Detecting running kernel from /proc/cmdline..."

VMLINUX=""
BOOT_IMAGE=""

# Extract BOOT_IMAGE
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        BOOT_IMAGE=*)
            BOOT_IMAGE="${arg#BOOT_IMAGE=}"
            break
            ;;
    esac
done

if [ -z "$BOOT_IMAGE" ]; then
    echo -e "${RED}[ERROR]${NC} BOOT_IMAGE not found in /proc/cmdline"
    exit 1
fi

# Resolve kernel path
if [ -f "$BOOT_IMAGE" ]; then
    VMLINUX="$BOOT_IMAGE"
elif [ -f "/boot$BOOT_IMAGE" ]; then
    VMLINUX="/boot$BOOT_IMAGE"
elif [ -f "/boot/$(basename "$BOOT_IMAGE")" ]; then
    VMLINUX="/boot/$(basename "$BOOT_IMAGE")"
else
    echo -e "${RED}[ERROR]${NC} Kernel image not found"
    echo "Tried:"
    echo "  $BOOT_IMAGE"
    echo "  /boot$BOOT_IMAGE"
    echo "  /boot/$(basename "$BOOT_IMAGE")"
    exit 1
fi

# Kernel real version
KVER="$(uname -r)"
# Kernel image (only name)
K_IMG_NAME=$(basename $BOOT_IMAGE)


if [ ! -d "/lib/modules/$KVER" ]; then
    echo -e "${RED}[ERROR]${NC} Kernel modules not found: /lib/modules/$KVER"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Kernel detected:"
echo "  BOOT_IMAGE : $K_IMG_NAME"
echo "  Kernel     : $VMLINUX"
echo "  Version    : $KVER"
echo "  Modules    : /lib/modules/$KVER"

# ----------------------------------------------------------
# KERNEL COPY
# ----------------------------------------------------------
CURRENT_SECTION="kernel copy"

cp "$VMLINUX" "$BOOT_DIR/${K_IMG_NAME}" || exit 1
chmod 0644 "$BOOT_DIR/${K_IMG_NAME}"

FULLVER="$KVER"

echo -e "${GREEN}[OK]${NC} Kernel copied to ISO"

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
  "$INITRAMFS/var/lock" \
  "$INITRAMFS/mnt/iso" \
  "$INITRAMFS/mnt/iso_test" \
  "$INITRAMFS/mnt/newroot" \
  "$INITRAMFS/mnt/ram" \
  "$INITRAMFS/mnt/ro_root" \
  "$INITRAMFS/lib/modules/$FULLVER"
  

CURRENT_SECTION="initramfs busybox shell setup"

BUSYBOX_BIN="$SCRIPT_DIR/initramfs/busybox"
BASH_BIN="$SCRIPT_DIR/initramfs/bash"
BUILD_TOOLS="$SCRIPT_DIR/build-tools.sh"

echo -e "${YELLOW}[INFO]${NC} Setting up initramfs shell environment..."

# ----------------------------------------------------------
# 1. Ensure busybox exists
# ----------------------------------------------------------
if [ ! -f "$BUSYBOX_BIN" ]; then
    echo "[WARN] busybox not found at:"
    echo "       $BUSYBOX_BIN"
    echo

    if [ -x "$BUILD_TOOLS" ]; then
        echo -e "${YELLOW}[INFO]${NC} Attempting to build busybox..."
        "$BUILD_TOOLS" --busybox || {
            echo -e "${RED}[ERROR]${NC} busybox build failed"
            exit 1
        }
    else
        echo -e "${RED}[ERROR]${NC} build-tools.sh not found or not executable"
        echo
        echo "Please run manually:"
        echo "  ./build-tools.sh --busybox"
        exit 1
    fi

    # Re-check
    if [ ! -f "$BUSYBOX_BIN" ]; then
        echo -e "${RED}[FATAL]${NC} busybox still missing after build attempt"
        exit 1
    fi

    echo -e "${GREEN}[OK]${NC} busybox successfully built"
fi

# ----------------------------------------------------------
# 2. Validate busybox binary
# ----------------------------------------------------------
if [ ! -x "$BUSYBOX_BIN" ]; then
    echo -e "${RED}[ERROR]${NC} busybox exists but is not executable"
    exit 1
fi

# Check that it runs
if ! "$BUSYBOX_BIN" --help >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${NC} busybox binary is not functional"
    exit 1
fi

# Check switch_root support
if ! "$BUSYBOX_BIN" --list | grep -q "^switch_root$"; then
    echo -e "${RED}[FATAL]${NC} busybox was built without switch_root support"
    echo "Rebuild busybox with CONFIG_SWITCH_ROOT=y"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} busybox validated"

# ----------------------------------------------------------
# 3. Install busybox into initramfs
# ----------------------------------------------------------
install -m 0755 "$BUSYBOX_BIN" "$INITRAMFS/bin/busybox"

# ----------------------------------------------------------
# 4. Optional bash support
# ----------------------------------------------------------
if [ -f "$BASH_BIN" ]; then
    echo -e "${GREEN}[OK]${NC} bash detected - using bash as /bin/sh"
    
    install -m 0755 "$BASH_BIN" "$INITRAMFS/bin/bash"

    (
        cd "$INITRAMFS/bin" || exit 1
        ./busybox --list | \
        grep -v "init" | \
        grep -v "poweroff" | \
        grep -v "reboot" | \
        grep -v "^sh$" | \
        while read app; do
            [ "$app" = "busybox" ] && continue
            ln -sf busybox "$app"
        done
    )

    ln -sf bash "$INITRAMFS/bin/sh"

else
    echo -e "${GREEN}[OK]${NC} bash not found - using busybox sh"

    (
        cd "$INITRAMFS/bin" || exit 1
        ./busybox --list | \
        grep -v "init" | \
        grep -v "poweroff" | \
        grep -v "reboot" | \
        while read app; do
            [ "$app" = "busybox" ] && continue
            ln -sf busybox "$app"
        done
    )
fi

# ----------------------------------------------------------
# 5. switch_root (always from busybox)
# ----------------------------------------------------------
ln -sf ../bin/busybox "$INITRAMFS/sbin/switch_root"


# ----------------------------------------------------------
# 6. Static fsck.ext4 & mkfs.ext4 (for overlay with zram)
# ----------------------------------------------------------
[ -x "$SCRIPT_DIR/initramfs/mkfs.ext4" ] && install -m 0755 "$SCRIPT_DIR/initramfs/mkfs.ext4" "$INITRAMFS/sbin/mkfs.ext4" && echo -e "${YELLOW}[INFO]${NC} mkfs.ext4 copied to INITRAMFS" || true
[ -x "$SCRIPT_DIR/initramfs/fsck.ext4" ] && install -m 0755 "$SCRIPT_DIR/initramfs/fsck.ext4" "$INITRAMFS/sbin/fsck.ext4" && echo -e "${YELLOW}[INFO]${NC} fsck.ext4 copied to INITRAMFS" || true


echo -e "${GREEN}[OK]${NC} initramfs shell environment ready"


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

# Módulos de red solo para netinstall
if [ "$NETINSTALL_MODE" = true ]; then
    echo -e "${YELLOW}[INFO]${NC} Adding network kernel modules (netinstall mode)..."
    NET_DIRS="
    kernel/drivers/net/ethernet/intel/e1000
    kernel/drivers/net/ethernet/intel/e1000e
    kernel/drivers/net/ethernet/realtek
    kernel/drivers/net/ethernet/broadcom
    kernel/drivers/net/ethernet/atheros
    kernel/drivers/net/usb
    kernel/drivers/net/virtio_net
    kernel/drivers/net/wireless/ath/ath5k
    kernel/drivers/net/wireless/ath/ath9k
    "
    for d in $NET_DIRS; do
        if [ -d "$MODDIR/$d" ]; then
            mkdir -p "$DEST/$d"
            cp -a "$MODDIR/$d" "$DEST/${d%/*}/"
        fi
    done
fi

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

# Avoid Bash (if enabled) "I have no name!"
ROOT_PASS_HASH=""
if command -v openssl >/dev/null 2>&1; then
    ROOT_PASS_HASH=$(openssl passwd -6 neonatox 2>/dev/null || true)
fi
if [ -z "$ROOT_PASS_HASH" ] && command -v python3 >/dev/null 2>&1; then
    ROOT_PASS_HASH=$(python3 -c 'import crypt; print(crypt.crypt("neonatox", crypt.mksalt(crypt.METHOD_SHA512)))' 2>/dev/null || true)
fi
if [ -z "$ROOT_PASS_HASH" ] && command -v python >/dev/null 2>&1; then
    ROOT_PASS_HASH=$(python -c 'import crypt; print(crypt.crypt("neonatox", crypt.mksalt(crypt.METHOD_SHA512)))' 2>/dev/null || true)
fi

cat > "$INITRAMFS/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
EOF
if [ -n "$ROOT_PASS_HASH" ]; then
    cat > "$INITRAMFS/etc/shadow" <<EOF
root:$ROOT_PASS_HASH:19875:0:99999:7:::
EOF
    chmod 0600 "$INITRAMFS/etc/shadow"
fi

# --------------------------------------------------
# NETINSTALL MODE: tools, nhopkg, bootstrap, init
# --------------------------------------------------
if [ "$NETINSTALL_MODE" = true ]; then

    # --- Auto-build required tools if missing ---
    echo -e "${YELLOW}[INFO]${NC} Netinstall: ensuring static bash..."
    if [ ! -f "$SCRIPT_DIR/initramfs/bash" ]; then
        echo -e "${YELLOW}[INFO]${NC} Building static bash..."
        "$BUILD_TOOLS" --bash || exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Netinstall: ensuring e2fsprogs..."
    if [ ! -f "$SCRIPT_DIR/initramfs/mkfs.ext4" ]; then
        echo -e "${YELLOW}[INFO]${NC} Building static e2fsprogs..."
        "$BUILD_TOOLS" --e2fsprogs || exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Netinstall: ensuring dropbear..."
    if [ ! -f "$SCRIPT_DIR/initramfs/dropbear" ]; then
        echo -e "${YELLOW}[INFO]${NC} Building static dropbear..."
        "$BUILD_TOOLS" --dropbear || exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Netinstall: ensuring wpa_supplicant..."
    if [ ! -f "$SCRIPT_DIR/initramfs/wpa_supplicant" ]; then
        echo -e "${YELLOW}[INFO]${NC} Building static wpa_supplicant..."
        "$BUILD_TOOLS" --wpa_supplicant || exit 1
    fi

    echo -e "${YELLOW}[INFO]${NC} Netinstall: ensuring static zstd..."
    if [ ! -f "$SCRIPT_DIR/initramfs/zstd" ]; then
        echo -e "${YELLOW}[INFO]${NC} Building static zstd..."
        "$BUILD_TOOLS" --zstd || exit 1
    fi

    # --- Copy netinstall binaries into initramfs ---
    echo -e "${YELLOW}[INFO]${NC} Copying netinstall tools to initramfs..."
    [ -f "$SCRIPT_DIR/initramfs/bash" ] && install -m 0755 "$SCRIPT_DIR/initramfs/bash" "$INITRAMFS/bin/bash"
    [ -f "$SCRIPT_DIR/initramfs/dropbear" ] && install -m 0755 "$SCRIPT_DIR/initramfs/dropbear" "$INITRAMFS/sbin/dropbear"
    [ -f "$SCRIPT_DIR/initramfs/dropbearkey" ] && install -m 0755 "$SCRIPT_DIR/initramfs/dropbearkey" "$INITRAMFS/sbin/dropbearkey"
    [ -f "$SCRIPT_DIR/initramfs/wpa_supplicant" ] && install -m 0755 "$SCRIPT_DIR/initramfs/wpa_supplicant" "$INITRAMFS/sbin/wpa_supplicant"
    [ -f "$SCRIPT_DIR/initramfs/wpa_cli" ] && install -m 0755 "$SCRIPT_DIR/initramfs/wpa_cli" "$INITRAMFS/bin/wpa_cli"
    [ -f "$SCRIPT_DIR/initramfs/wpa_passphrase" ] && install -m 0755 "$SCRIPT_DIR/initramfs/wpa_passphrase" "$INITRAMFS/bin/wpa_passphrase"
    [ -f "$SCRIPT_DIR/initramfs/mkfs.ext4" ] && install -m 0755 "$SCRIPT_DIR/initramfs/mkfs.ext4" "$INITRAMFS/sbin/mkfs.ext4"
    [ -f "$SCRIPT_DIR/initramfs/fsck.ext4" ] && install -m 0755 "$SCRIPT_DIR/initramfs/fsck.ext4" "$INITRAMFS/sbin/fsck.ext4"
    [ -f "$SCRIPT_DIR/initramfs/zstd" ] && install -m 0755 "$SCRIPT_DIR/initramfs/zstd" "$INITRAMFS/bin/zstd"
    for L in unzstd zstdcat zstdmt; do
        [ -f "$INITRAMFS/bin/zstd" ] && ln -svf zstd "$INITRAMFS/bin/$L"
    done
    echo -e "${GREEN}[OK]${NC} Netinstall tools copied"

    # --- nhopkg (clone + meson install) ---
    echo -e "${YELLOW}[INFO]${NC} Cloning nhopkg..."
    rm -rf /tmp/nhopkg 2>/dev/null || true
    git clone https://github.com/cargabsj175/neonatox-nhopkg.git /tmp/nhopkg 2>/dev/null || {
        echo -e "${RED}[ERROR]${NC} nhopkg clone failed" >&2
        exit 1
    }

    echo -e "${YELLOW}[INFO]${NC} Installing nhopkg into initramfs..."
    (
        cd /tmp/nhopkg
        sed -i 's/^NHOPKG_GETTEXT=.*/NHOPKG_GETTEXT=no/' src/nhopkg.conf.in 2>/dev/null
        meson setup build 2>/dev/null
        cd build
        DESTDIR="$PWD/DESTDIR" ninja install 2>/dev/null
        cp -rv "$PWD/DESTDIR/"* "$INITRAMFS/" 2>/dev/null
    )
    echo -e "${GREEN}[OK]${NC} nhopkg installed"

    # --- neonatox-bootstrap (clone + copy) ---
    echo -e "${YELLOW}[INFO]${NC} Cloning neonatox-bootstrap..."
    rm -rf /tmp/neonatox-bootstrap 2>/dev/null || true
    git clone https://github.com/cargabsj175/neonatox-bootstrap.git /tmp/neonatox-bootstrap 2>/dev/null || {
        echo -e "${RED}[WARN]${NC} neonatox-bootstrap clone failed (non-fatal)"
    }

    if [ -d /tmp/neonatox-bootstrap ]; then
        cp -r /tmp/neonatox-bootstrap "$INITRAMFS/" 2>/dev/null || true
        mkdir -p "$INITRAMFS/var/nhopkg/cache" \
                 "$INITRAMFS/var/nhopkg/files" \
                 "$INITRAMFS/var/nhopkg/logs" \
                 "$INITRAMFS/var/nhopkg/packages" \
                 "$INITRAMFS/var/nhopkg/repo"
        echo -e "${GREEN}[OK]${NC} neonatox-bootstrap copied"
    fi

    # --- Shell profile (ash/bash compatible) ---
    cat > "$INITRAMFS/etc/profile" << 'PROFILE'
NORMAL="\[\e[0m\]"
RED="\[\e[1;31m\]"
GREEN="\[\e[1;32m\]"
if [[ $EUID == 0 ]] ; then
  PS1="$RED\u [ $NORMAL\w$RED ]# $NORMAL"
else
  PS1="$GREEN\u [ $NORMAL\w$GREEN ]\$ $NORMAL"
fi

unset RED GREEN NORMAL

echo "GNU Neonatox @ $(uname -m)"
	echo ""
PROFILE
    chmod 0644 "$INITRAMFS/etc/profile"

    # --- Fake tools for nhopkg (meson, ninja, git) ---
    for _fake in "$SCRIPT_DIR/initramfs/fake-"*; do
        [ -f "$_fake" ] || continue
        _name="${_fake##*/}"
        _target="${INITRAMFS}/bin/${_name#fake-}"
        install -m 0755 "$_fake" "$_target"
        echo -e "${GREEN}[OK]${NC} Fake tool: ${_name#fake-}"
    done

    # --- udhcpc default script (needed by busybox udhcpc) ---
    mkdir -p "$INITRAMFS/usr/share/udhcpc"
    cat > "$INITRAMFS/usr/share/udhcpc/default.script" << 'UDHCPC'
#!/bin/sh
case "$1" in
    bound|renew)
        ifconfig $interface $ip netmask $subnet
        [ -n "$router" ] && route add default gw $router
        [ -n "$dns" ] && echo "nameserver $dns" > /etc/resolv.conf
        ;;
    deconfig)
        ifconfig $interface 0.0.0.0
        ;;
esac
UDHCPC
    chmod 0755 "$INITRAMFS/usr/share/udhcpc/default.script"

    # --- wifi-config.sh ---
    install -m 0755 "$SCRIPT_DIR/initramfs/wifi-config.sh" "$INITRAMFS/wifi-config.sh"

    # --- Init: netinstall PID 1 ---
    install -m 0755 "$SCRIPT_DIR/initramfs/netinstall-init.sh" "$INITRAMFS/init"
    echo -e "${GREEN}[OK]${NC} netinstall PID 1 ready"

else
    # --------------------------------------------------
    # LIVE MODE: standard init + live-config
    # --------------------------------------------------
    install -m 0755 "$SCRIPT_DIR/initramfs/init" "$INITRAMFS/init"
    install -m 0755 "$SCRIPT_DIR/initramfs/live-config.sh" "$INITRAMFS/live-config.sh"
    install -m 0644 "$ROOTFS_HASH_FILE" "$INITRAMFS/rootfs.sha256"
fi


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

if [ "$NETINSTALL_MODE" = true ]; then

menuentry "${ISO_NAME%-live} Net Install" {
    linux /boot/${K_IMG_NAME} quiet netinstall=1 loglevel=3
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} Net Install (Debug)" {
    linux /boot/${K_IMG_NAME} netinstall=1 debug=1 loglevel=7
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} Net Install (Initramfs debug)" {
    linux /boot/${K_IMG_NAME} quiet netinstall=1 initrd_debug=1
    initrd /boot/initramfs.img
}

else

menuentry "${ISO_NAME%-live} ${VERSION} live" {
    linux /boot/${K_IMG_NAME} quiet loglevel=3 zram=1
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} ${VERSION} live (Language & Live User Config)" {
    linux /boot/${K_IMG_NAME} quiet neoconfig=1 zram=1
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} ${VERSION} live (Failsafe graphics)" {
    linux /boot/${K_IMG_NAME} quiet nomodeset vga=normal zram=1
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} ${VERSION} live (DEBUG)" {
    linux /boot/${K_IMG_NAME} debug=1 loglevel=7 zram=1
    initrd /boot/initramfs.img
}

menuentry "${ISO_NAME%-live} ${VERSION} live (Initramfs debug)" {
    linux /boot/${K_IMG_NAME} quiet initrd_debug=1 zram=1
    initrd /boot/initramfs.img
}

fi

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
if [ "$WITHOUT_MAKE_ISO" = false ]; then
CURRENT_SECTION="final iso build"

echo -e "${YELLOW}[INFO]${NC} Building final ISO..."

if [ "$NETINSTALL_MODE" = true ]; then
    ISO_NAME="${BASE_NAME}-netinstall"
fi

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
fi
