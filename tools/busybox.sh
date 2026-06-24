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

cd "$SRC_DIR"

# ----------------------------------------------------------
# Clone source if missing
# ----------------------------------------------------------
if [ ! -d busybox ]; then
    git clone https://git.busybox.net/busybox
fi

cd busybox

cp ../busybox-config .config
echo -e "${YELLOW}[INFO]${NC} Configuration copied"

# ----------------------------------------------------------
# Force static
# ----------------------------------------------------------
sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config || true

echo -e "${YELLOW}[INFO]${NC} Updating config..."
yes "" | make oldconfig

JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

make CC="$MUSLGCC" -j"$JOBS"


# ----------------------------------------------------------
# Validate static build
# ----------------------------------------------------------
file busybox | grep -q "statically linked" || {
    echo -e "${RED}[ERROR]${NC} Busybox is not static!"
    exit 1
}

DEST="$OUT_DIR"
mkdir -p "$DEST"

install -m755 busybox "$DEST/busybox"

echo -e "${GREEN}[DONE]${NC} Busybox ready at $DEST"
