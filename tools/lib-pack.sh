#!/bin/sh
# ==========================================================
# Neonatox tools: packaging / fetching / manifest helpers
# Shared by build-tools.sh and publish.sh
# Requires TOOLS_DIR and OUT_DIR set by the sourcer.
# ==========================================================

# ----------------------------------------------------------
# Detect architecture
# ----------------------------------------------------------
detect_arch() {
    case "$(uname -m)" in
        x86_64)           echo "x86_64" ;;
        aarch64|arm64)    echo "aarch64" ;;
        *)                echo "$(uname -m)" ;;
    esac
}

# ----------------------------------------------------------
# Current tools release tag (tools-*)
# TOOLS_TAG overrides; otherwise nearest tools-* git tag.
# ----------------------------------------------------------
current_tools_tag() {
    if [ -n "$TOOLS_TAG" ]; then
        echo "$TOOLS_TAG"
        return 0
    fi
    TAG="$(git -C "$TOOLS_DIR/.." describe --tags --abbrev=0 2>/dev/null || true)"
    case "$TAG" in
        tools-*) echo "$TAG" ;;
        *)       echo "tools-dev" ;;
    esac
}

# ----------------------------------------------------------
# Tool version: read OUT_DIR/<tool>.version (written by the
# tool build script after install).
# ----------------------------------------------------------
tool_version() {
    VF="$OUT_DIR/$1.version"
    if [ -f "$VF" ]; then
        cat "$VF"
    else
        echo "unknown"
    fi
}

# ----------------------------------------------------------
# Binaries shipped per tool (names inside OUT_DIR)
# ----------------------------------------------------------
tool_binaries() {
    case "$1" in
        busybox)        echo "busybox" ;;
        bash)           echo "bash" ;;
        e2fsprogs)      echo "mkfs.ext4 fsck.ext4" ;;
        dropbear)       echo "dropbear dropbearkey" ;;
        btrfsprogs)     echo "btrfs mkfs.btrfs" ;;
        wpa_supplicant) echo "wpa_supplicant wpa_cli wpa_passphrase" ;;
        zstd)           echo "zstd" ;;
        *)              echo "" ;;
    esac
}

manifest_path() { echo "$TOOLS_DIR/releases.sha256"; }

# ----------------------------------------------------------
# Package built binaries of a tool into tools/dist/<zip>
# Zip name: neonatox-<tool>-<ver>-<arch>-<rev>.zip
# ----------------------------------------------------------
package_tool() {
    TOOL="$1"
    REV="${BUILD_REV:-r1}"
    ARCH="$(detect_arch)"
    VER="$(tool_version "$TOOL")"
    BINS="$(tool_binaries "$TOOL")"

    [ -z "$BINS" ] && { echo "[ERROR] unknown tool: $TOOL"; return 1; }

    for b in $BINS; do
        [ -f "$OUT_DIR/$b" ] || {
            echo "[WARN] $TOOL: missing $OUT_DIR/$b, skip"
            return 1
        }
    done

    DIST="$TOOLS_DIR/dist"
    mkdir -p "$DIST"
    ZIP="$DIST/neonatox-$TOOL-$VER-$ARCH-$REV.zip"

    TMP="$DIST/.tmp-$TOOL"
    rm -rf "$TMP"
    mkdir -p "$TMP"
    for b in $BINS; do
        cp -a "$OUT_DIR/$b" "$TMP/$b"
    done

    ( cd "$TMP" && sha256sum $BINS > SHA256SUMS )

    ( cd "$TMP" && zip -q -9 "$ZIP" $BINS SHA256SUMS >/dev/null 2>&1 ) || {
        rm -rf "$TMP"
        echo "[ERROR] zip packaging failed for $TOOL"
        return 1
    }
    rm -rf "$TMP"

    echo "[OK] $TOOL -> $ZIP"
}

# ----------------------------------------------------------
# Add/update the manifest entry for a tool
# ----------------------------------------------------------
manifest_add() {
    TOOL="$1"
    VER="$(tool_version "$TOOL")"
    ARCH="$(detect_arch)"
    REV="${BUILD_REV:-r1}"
    TAG="$(current_tools_tag)"
    ZIP="$TOOLS_DIR/dist/neonatox-$TOOL-$VER-$ARCH-$REV.zip"

    [ -f "$ZIP" ] || { echo "[ERROR] $ZIP not found"; return 1; }

    SHASUM="$(sha256sum "$ZIP" | awk '{print $1}')"
    ASSET="$(basename "$ZIP")"

    MAN="$(manifest_path)"
    [ -f "$MAN" ] || printf '# tool toolver arch rev sha256 release_tag asset\n' > "$MAN"
    grep -v "^$TOOL " "$MAN" > "$MAN.tmp" 2>/dev/null || true
    printf '%s %s %s %s %s %s %s\n' \
        "$TOOL" "$VER" "$ARCH" "$REV" "$SHASUM" "$TAG" "$ASSET" >> "$MAN.tmp"
    mv "$MAN.tmp" "$MAN"
    echo "[OK] manifest updated for $TOOL ($TAG)"
}

# ----------------------------------------------------------
# unzip helper (unzip binary o applet de busybox)
# ----------------------------------------------------------
unzip_cmd() {
    if command -v unzip >/dev/null 2>&1; then
        unzip "$@"
    elif command -v busybox >/dev/null 2>&1 && busybox 2>&1 | tr ',' '\n' | grep -q ' unzip'; then
        busybox unzip "$@"
    else
        echo "[ERROR] no unzip available (install 'unzip' or busybox)" >&2
        return 1
    fi
}

# ----------------------------------------------------------
# Download + verify + extract a prebuilt tool from releases
# ----------------------------------------------------------
fetch_tool() {
    TOOL="$1"
    MAN="$(manifest_path)"
    LINE="$(grep "^$TOOL " "$MAN" 2>/dev/null | head -1)"

    [ -z "$LINE" ] && {
        echo "[ERROR] no prebuilt entry for '$TOOL' in $MAN"
        echo "        Compile it:   ./build-tools.sh --$TOOL"
        echo "        Or publish:   ./build-tools.sh --package-all && ./tools/publish.sh"
        return 1
    }

    # shellcheck disable=SC2086
    set -- $LINE
    VER="$2"; ARCH="$3"; REV="$4"; SHASUM="$5"; TAG="$6"; ASSET="$7"

    REPO="${TOOLS_REPO:-NeonatoX/neonatox-live-boot}"
    BASE_URL="${TOOLS_BASE_URL:-https://github.com/$REPO/releases/download}"
    URL="$BASE_URL/$TAG/$ASSET"

    mkdir -p "$OUT_DIR"
    TMP="$OUT_DIR/.fetch-$ASSET"

    echo "[INFO] Downloading $URL"
    wget -q -O "$TMP" "$URL" || { echo "[ERROR] download failed"; rm -f "$TMP"; return 1; }

    ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"
    if [ "$ACTUAL" != "$SHASUM" ]; then
        echo "[ERROR] sha256 mismatch: expected $SHASUM, got $ACTUAL"
        rm -f "$TMP"
        return 1
    fi

    for b in $(tool_binaries "$TOOL"); do
        rm -f "$OUT_DIR/$b"
        unzip_cmd -o "$TMP" "$b" -d "$OUT_DIR" >/dev/null 2>&1 || {
            echo "[ERROR] failed to extract $b from zip"
            rm -f "$TMP"
            return 1
        }
    done
    rm -f "$TMP"

    echo "$VER" > "$OUT_DIR/$TOOL.version"

    for b in $(tool_binaries "$TOOL"); do
        file "$OUT_DIR/$b" | grep -q "statically linked" || {
            echo "[ERROR] $b is not statically linked"
            return 1
        }
    done

    echo "[OK] $TOOL fetched from $TAG ($ASSET)"
}
