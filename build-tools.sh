#!/bin/sh
set -e

# ==========================================================
# Neonatox Tools Builder - source compilation framework
# Carlos Sanchez - 2007-2026
# ==========================================================

PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NLB_VERSION="v0.9"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
TOOLS_DIR="$SCRIPT_DIR/tools"
SRC_DIR="$TOOLS_DIR/src"
OUT_DIR="$TOOLS_DIR/output"
export SRC_DIR OUT_DIR

. "$TOOLS_DIR/lib-pack.sh"

clear 2>/dev/null || true
echo -e "${YELLOW}========${NC} ${GREEN}Neonatox Live Boot Tools Builder - ${NLB_VERSION} Carlos Sanchez - 2007-2026 ${YELLOW}========${NC}"
echo -e "${YELLOW}==========${NC} https://github.com/cargabsj175/neonatox-live-boot ${YELLOW}=========${NC}"

# ----------------------------------------------------------
# HELP
# ----------------------------------------------------------
show_help() {
cat <<EOF

Usage:
  ./build-tools.sh [OPTIONS]

Options:
  --all             Build all available tools
  --toolname        Build specific tool
  --package-all     Package built binaries into versioned zips (tools/dist/) + update manifest
  --package TOOL    Package a single tool
  --fetch-all       Download all prebuilt tools from GitHub releases
  --fetch TOOL      Download a prebuilt tool from GitHub releases
  --list            List available tools
  --clean           Clean build artifacts inside tools/
  --version         Shows version
  --help            Show this help

Examples:
  ./build-tools.sh --all
  ./build-tools.sh --busybox
  ./build-tools.sh --package-all
  ./build-tools.sh --fetch busybox
  ./build-tools.sh --fetch-all

EOF
}

show_ver(){
echo "Neonatox Live Boot Tools Builder - ${NLB_VERSION} Carlos Sanchez - 2007-2026"
}

# ----------------------------------------------------------
# AUTO DISCOVER AVAILABLE TOOLS
# ----------------------------------------------------------
AVAILABLE_TOOLS="$(cd "$TOOLS_DIR" 2>/dev/null && ls *.sh 2>/dev/null | sed 's/.sh$//' | grep -v -E '^(lib-pack|publish)$' | tr '\n' ' ')"

# ----------------------------------------------------------
# BUILD DISPATCHER
# ----------------------------------------------------------
build_tool() {
    TOOL="$1"
    FILE="$TOOLS_DIR/$TOOL.sh"

    if [ ! -f "$FILE" ]; then
        echo -e "${RED}[ERROR]${NC} Tool not found: $TOOL"
        exit 1
    fi

    # Busybox: usar el del sistema si está en PATH
    if [ "$TOOL" = "busybox" ] && command -v busybox >/dev/null 2>&1; then
        echo -e "${YELLOW}[INFO]${NC} busybox found in PATH, copying to output..."
        mkdir -p "$OUT_DIR"
        cp "$(command -v busybox)" "$OUT_DIR/busybox"
        BUSYBOX_VER="$("$OUT_DIR/busybox" 2>&1 | head -1 | sed -n 's/.*BusyBox v\([0-9][0-9.]*\).*/\1/p')"
        echo "${BUSYBOX_VER:-system}" > "$OUT_DIR/busybox.version"
        echo -e "${GREEN}[OK]${NC} busybox ready at $OUT_DIR/busybox"
        return 0
    fi

    echo "------------------------------------------------------------"
    echo -e "${BLUE}[BUILD]${NC} $TOOL"
    echo "------------------------------------------------------------"
    
    cd "$TOOLS_DIR"
    sh "$FILE"
    cd ..

    echo -e "${GREEN}[OK]${NC} $TOOL finished"
    echo
}

# ----------------------------------------------------------
# CLEAN TOOLS
# ----------------------------------------------------------
clean_tools() {
    echo "------------------------------------------------------------"
    echo -e "${BLUE}[CLEAN]${NC} Cleaning tools directory"
    echo "------------------------------------------------------------"

    if [ ! -d "$TOOLS_DIR" ]; then
        echo -e "${RED}[ERROR]${NC} tools directory not found"
        exit 1
    fi

    cd "$TOOLS_DIR"

    # === CUSTOM CLEAN COMMANDS ===
    # Agrega aquí lo que quieras eliminar

    echo -e "${YELLOW}[INFO]${NC} Removing tar archives..."
    rm -f src/*.tar.* 2>/dev/null || true

   echo -e "${YELLOW}[INFO]${NC} Removing extracted source dirs..."
    rm -rf src/*/ 2>/dev/null || true

    echo -e "${YELLOW}[INFO]${NC} Removing build leftovers..."
    rm -f src/*.log src/*.tmp 2>/dev/null || true

    echo -e "${YELLOW}[INFO]${NC} Removing packaged zips..."
    rm -rf "$TOOLS_DIR/dist" 2>/dev/null || true

    cd "$SCRIPT_DIR"

    echo -e "${GREEN}[OK]${NC} Clean finished"
    echo
}


# ----------------------------------------------------------
# ARGUMENT PARSER
# ----------------------------------------------------------
[ $# -eq 0 ] && { show_help; exit 1; }

while [ $# -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in
        --all)
            for t in $AVAILABLE_TOOLS; do
                build_tool "$t"
            done
            exit 0
        ;;
        --list)
            echo "Available tools:"
            for t in $AVAILABLE_TOOLS; do
                echo "  --$t"
            done
            exit 0
        ;;
        --version|-v)
            show_ver
            exit 0
        ;;
        --help|-h)
            show_help
            exit 0
        ;;
        --clean)
            clean_tools
            exit 0
        ;;
        --package-all)
            for t in $AVAILABLE_TOOLS; do
                if package_tool "$t"; then
                    manifest_add "$t"
                fi
            done
            exit 0
        ;;
        --package)
            [ $# -eq 0 ] && { echo -e "${RED}[ERROR]${NC} --package requires a tool name"; exit 1; }
            TOOL="$1"
            shift
            if package_tool "$TOOL"; then
                manifest_add "$TOOL"
            else
                exit 1
            fi
            exit 0
        ;;
        --fetch-all)
            for t in $AVAILABLE_TOOLS; do
                fetch_tool "$t" || true
            done
            exit 0
        ;;
        --fetch)
            [ $# -eq 0 ] && { echo -e "${RED}[ERROR]${NC} --fetch requires a tool name"; exit 1; }
            TOOL="$1"
            shift
            fetch_tool "$TOOL" || exit 1
            exit 0
        ;;
        --*)
            TOOL="${arg#--}"
            build_tool "$TOOL"
        ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $arg"
            exit 1
        ;;
    esac
done
