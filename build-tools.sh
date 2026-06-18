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

clear
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
  --list            List available tools
  --clean           Clean build artifacts inside tools/
  --version         Shows version
  --help            Show this help

Examples:
  ./build-tools.sh --all
  ./build-tools.sh --busybox
  ./build-tools.sh --bash --busybox

EOF
}

show_ver(){
echo "Neonatox Live Boot Tools Builder - ${NLB_VERSION} Carlos Sanchez - 2007-2026"
}

# ----------------------------------------------------------
# AUTO DISCOVER AVAILABLE TOOLS
# ----------------------------------------------------------
AVAILABLE_TOOLS="$(cd "$TOOLS_DIR" 2>/dev/null && ls *.sh 2>/dev/null | sed 's/.sh$//')"

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
    rm -f *.tar.* 2>/dev/null || true

   echo -e "${YELLOW}[INFO]${NC} Removing extracted source dirs..."
    rm -rf */ 2>/dev/null || true

   echo -e "${YELLOW}[INFO]${NC} Removing build leftovers..."
    rm -f *.log *.tmp 2>/dev/null || true

    cd "$SCRIPT_DIR"

    echo -e "${GREEN}[OK]${NC} Clean finished"
    echo
}


# ----------------------------------------------------------
# ARGUMENT PARSER
# ----------------------------------------------------------
[ $# -eq 0 ] && { show_help; exit 1; }

for arg in "$@"; do
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
