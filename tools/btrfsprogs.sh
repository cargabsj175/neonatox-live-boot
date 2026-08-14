#!/bin/sh
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${YELLOW}[INFO]${NC} Searching for musl compiler..."
for cc in musl-gcc x86_64-linux-musl-gcc; do
    MUSLGCC=$(command -v "$cc" 2>/dev/null || true)
    [ -n "$MUSLGCC" ] && break
done
if [ -z "$MUSLGCC" ]; then
    echo -e "${RED}[ERROR]${NC} musl compiler not found in PATH" >&2
    exit 1
fi
echo -e "${YELLOW}[INFO]${NC} Using compiler: $MUSLGCC"

cd "$SRC_DIR"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
DEPS_PREFIX="/tmp/btrfs-deps"
rm -rf "$DEPS_PREFIX"
mkdir -p "$DEPS_PREFIX/lib" "$DEPS_PREFIX/include"

# ----------------------------------------------------------
# Build zlib static
# ----------------------------------------------------------
ZLIB_V="1.3.2"
ZLIB_ARCHIVE="zlib-$ZLIB_V.tar.gz"
ZLIB_URL="https://zlib.net/$ZLIB_ARCHIVE"

if [ ! -d "zlib-$ZLIB_V" ]; then
    [ -f "$ZLIB_ARCHIVE" ] || wget "$ZLIB_URL"
    tar xf "$ZLIB_ARCHIVE"
fi
cd "zlib-$ZLIB_V"
[ -f Makefile ] && make distclean || true
CC="$MUSLGCC" CFLAGS="-static -Os -s -std=gnu11" \
./configure --static --prefix="$DEPS_PREFIX"
make -j$JOBS
make install
cd "$SRC_DIR"

# ----------------------------------------------------------
# Build util-linux (minimal: libuuid + libblkid static)
# ----------------------------------------------------------
UL_V="2.40.4"
UL_ARCHIVE="util-linux-$UL_V.tar.gz"
UL_URL="https://mirrors.kernel.org/pub/linux/utils/util-linux/v${UL_V%.*}/$UL_ARCHIVE"

if [ ! -d "util-linux-$UL_V" ]; then
    [ -f "$UL_ARCHIVE" ] || wget "$UL_URL"
    tar xf "$UL_ARCHIVE"
fi
cd "util-linux-$UL_V"
[ -f Makefile ] && make distclean || true
CC="$MUSLGCC" \
CFLAGS="-static -Os -s -std=gnu11" \
LDFLAGS="-static" \
./configure \
    --host=x86_64-linux-musl \
    --disable-all-programs \
    --enable-libuuid --enable-libblkid \
    --disable-shared --enable-static \
    --prefix="$DEPS_PREFIX"
make -j$JOBS
make install
cd "$SRC_DIR"

# ----------------------------------------------------------
# Build btrfs-progs static
# ----------------------------------------------------------
BTRFS_V="7.0"
BTRFS_ARCHIVE="btrfs-progs-v${BTRFS_V}.tar.gz"
BTRFS_URL="https://mirrors.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/${BTRFS_ARCHIVE}"

if [ ! -d "btrfs-progs-v${BTRFS_V}" ]; then
    [ -f "$BTRFS_ARCHIVE" ] || wget "$BTRFS_URL"
    tar xf "$BTRFS_ARCHIVE"
fi
cd "btrfs-progs-v${BTRFS_V}"
[ -f Makefile ] && make distclean || true

export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"
export CFLAGS="-static -Os -s -std=gnu11 -I$DEPS_PREFIX/include"
export LDFLAGS="-static -L$DEPS_PREFIX/lib"

CC="$MUSLGCC" \
./configure \
    --host=x86_64-linux-musl \
    --disable-documentation \
    --disable-backtrace \
    --disable-convert \
    --disable-zoned \
    --disable-zstd \
    --disable-lzo \
    --disable-libudev \
    --disable-python \
    --disable-shared \
    --enable-static \
    --with-crypto=builtin

echo -e "${YELLOW}[INFO]${NC} Compiling btrfs and mkfs.btrfs..."
make -j$JOBS btrfs mkfs.btrfs

for bin in btrfs mkfs.btrfs; do
    if [ -f "$bin" ] && ! file "$bin" | grep -q "statically linked"; then
        echo -e "${RED}[ERROR]${NC} $bin is not static!"
        exit 1
    fi
done
echo -e "${GREEN}[OK]${NC} Static btrfs binaries verified"

DEST="$OUT_DIR"
mkdir -p "$DEST"
install -m755 btrfs       "$DEST/btrfs"
install -m755 mkfs.btrfs  "$DEST/mkfs.btrfs"

echo "$BTRFS_V" > "$DEST/btrfsprogs.version"

echo -e "${GREEN}[DONE]${NC} btrfs binaries copied to initramfs"
