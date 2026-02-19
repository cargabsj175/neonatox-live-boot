#!/bin/sh
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

VERSION="5.2.37"
ARCHIVE="bash-$VERSION.tar.gz"
URL="https://ftp.gnu.org/gnu/bash/$ARCHIVE"

# ----------------------------------------------------------
# Download source if missing
# ----------------------------------------------------------
if [ ! -d "bash-$VERSION" ]; then
    if [ ! -f "$ARCHIVE" ]; then
        echo -e "${YELLOW}[INFO]${NC} Downloading Bash source..."
        wget "$URL"
    fi

    echo -e "${YELLOW}[INFO]${NC} Extracting source..."
    tar xf "$ARCHIVE"
fi

cd "bash-$VERSION"

echo -e "${YELLOW}[INFO]${NC} Configuring static Bash..."

[ -f Makefile ] && make distclean || true

CC="$MUSLGCC" CFLAGS="-static -Os -s" LDFLAGS="-static" \
./configure   --host=x86_64-linux-musl \
              --enable-static-link \
              --without-bash-malloc \
              --disable-largefile \
              --disable-nls \
              --prefix=/

JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

echo -e "${YELLOW}[INFO]${NC} Compiling..."
make -j$JOBS bash

# ----------------------------------------------------------
# Validate static build
# ----------------------------------------------------------
if ! file bash | grep -q "statically linked"; then
    echo -e "${RED}[ERROR]${NC} Bash is not static!"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Static Bash verified"

DEST="../../initramfs"
mkdir -p "$DEST"

install -m755 bash "$DEST/bash"

echo -e "${GREEN}[DONE]${NC} Bash copied to initramfs"

