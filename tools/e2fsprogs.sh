#!/bin/sh
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[INFO]${NC} Searching for musl compiler..."

for cc in musl-gcc x86_64-linux-musl-gcc aarch64-linux-musl-gcc; do
    MUSLGCC=$(command -v "$cc" 2>/dev/null || true)
    [ -n "$MUSLGCC" ] && break
done

if [ -z "$MUSLGCC" ]; then
    echo -e "${RED}[ERROR]${NC} musl compiler not found in PATH" >&2
    exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Using compiler: $MUSLGCC"

cd "$SRC_DIR"

VERSION="1.47.1"
ARCHIVE="e2fsprogs-${VERSION}.tar.gz"
URL="https://sourceforge.net/projects/e2fsprogs/files/e2fsprogs/v${VERSION}/${ARCHIVE}/download"

# ----------------------------------------------------------
# Download source if missing
# ----------------------------------------------------------
if [ ! -d "e2fsprogs-${VERSION}" ]; then
    if [ ! -f "$ARCHIVE" ]; then
        echo -e "${YELLOW}[INFO]${NC} Downloading e2fsprogs source..."
        wget -O "$ARCHIVE" "$URL" || {
            echo -e "${RED}[ERROR]${NC} Download failed" >&2
            exit 1
        }
    fi

    echo -e "${YELLOW}[INFO]${NC} Extracting source..."
    tar xf "$ARCHIVE"
fi

cd "e2fsprogs-${VERSION}"

echo -e "${YELLOW}[INFO]${NC} Configuring static e2fsprogs (minimal for initramfs)..."

[ -f Makefile ] && make distclean || true

# ----------------------------------------------------------
# Minimalist + static setup
# ----------------------------------------------------------

export UUID_LIBS=""
export UUID_CFLAGS=""
export BLKID_LIBS=""
export BLKID_CFLAGS=""

CC="$MUSLGCC" \
CFLAGS="-static -Os -s -fno-stack-protector -U_FORTIFY_SOURCE" \
LDFLAGS="-static" \
./configure \
    --host=x86_64-linux-musl \
    --build=$(gcc -dumpmachine) \
    --disable-fsck \
    --disable-e2initrd-helper \
    --disable-tls \
    --disable-nls \
    --disable-debugfs \
    --disable-imager \
    --disable-resizer \
    --disable-defrag \
    --disable-rpath \
    --disable-backtrace \
    --prefix=/

JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

echo -e "${YELLOW}[INFO]${NC} Compiling essential parts..."
make -j"$JOBS" libs
make -j"$JOBS" -C misc mke2fs tune2fs badblocks
make -j"$JOBS" -C e2fsck e2fsck

# ----------------------------------------------------------
# Strip para reducir tamaño
# ----------------------------------------------------------
find . -type f -executable -exec strip --strip-unneeded {} \; 2>/dev/null || true

# ----------------------------------------------------------
# Validate static build
# ----------------------------------------------------------
for bin in misc/mke2fs e2fsck/e2fsck misc/tune2fs; do
    if [ -f "$bin" ] && ! file "$bin" | grep -q "statically linked"; then
        echo -e "${RED}[ERROR]${NC} $bin is not static!"
        exit 1
    fi
done

echo -e "${GREEN}[OK]${NC} Static binaries verified"

DEST="$OUT_DIR"
mkdir -p "$DEST"

# Copy ONLY the real binaries
install -m755 misc/mke2fs    "$DEST/mkfs.ext4"
install -m755 e2fsck/e2fsck  "$DEST/fsck.ext4"
# install -m755 misc/tune2fs   "$DEST/tune2fs"
# install -m755 misc/badblocks "$DEST/badblocks"

echo -e "${GREEN}[DONE]${NC} Binaries copied to initramfs"
