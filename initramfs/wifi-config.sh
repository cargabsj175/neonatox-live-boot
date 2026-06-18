#!/bin/sh
# /wifi-config.sh
# WiFi configuration for netinstall mode
# Requires: wpa_supplicant, wpa_cli, wpa_passphrase, iw, udhcpc

# --------------------------------------------------
# Colors
# --------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WIFI_IFACE=""

# --------------------------------------------------
# Core functions
# --------------------------------------------------
emergency_shell() {
    echo -e "${RED}[EMERGENCY]${NC} Dropping to shell"
    exec sh
}


# --------------------------------------------------
# Find WiFi interface
# --------------------------------------------------
find_wifi_iface() {
    for iface in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
        WIFI_IFACE="$iface"
        return 0
    done
    return 1
}

# --------------------------------------------------
# Scan networks
# --------------------------------------------------
scan_networks() {
    echo -e "${YELLOW}[INFO]${NC} Scanning WiFi networks..."
    iw dev "$WIFI_IFACE" scan 2>/dev/null | grep "^SSID:" | sort -u | sed 's/^SSID: //'
}

# --------------------------------------------------
# Connect to WPA/WPA2 network
# --------------------------------------------------
connect_wpa() {
    SSID="$1"
    PSK="$2"

    # Prefer wpa_passphrase if available, fall back to wpa_cli
    if command -v wpa_passphrase >/dev/null 2>&1; then
        CONF="/tmp/wpa.conf"
        wpa_passphrase "$SSID" "$PSK" > "$CONF" 2>/dev/null
        wpa_supplicant -B -i "$WIFI_IFACE" -c "$CONF" 2>/dev/null
    else
        # Use wpa_cli (wpa_supplicant does PSK hashing internally)
        wpa_supplicant -B -i "$WIFI_IFACE" -C /var/run/wpa_supplicant 2>/dev/null
        sleep 1
        wpa_cli -i "$WIFI_IFACE" add_network 2>/dev/null
        wpa_cli -i "$WIFI_IFACE" set_network 0 ssid "\"$SSID\"" 2>/dev/null
        wpa_cli -i "$WIFI_IFACE" set_network 0 psk "\"$PSK\"" 2>/dev/null
        wpa_cli -i "$WIFI_IFACE" enable_network 0 2>/dev/null
    fi

    echo -e "${YELLOW}[INFO]${NC} Waiting for association..."
    sleep 3

    udhcpc -i "$WIFI_IFACE" -n -q 2>/dev/null

    if ip -4 addr show "$WIFI_IFACE" | grep -q 'inet '; then
        echo -e "${GREEN}[OK]${NC} WiFi connected: $SSID"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to get IP on $SSID"
        return 1
    fi
}

# --------------------------------------------------
# Interactive mode
# --------------------------------------------------
interactive() {
    echo ""
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${GREEN}       CONFIGURACION WIFI${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"

    if ! find_wifi_iface; then
        echo -e "${RED}[ERROR]${NC} No WiFi interface found"
        emergency_shell
    fi

    ip link set "$WIFI_IFACE" up 2>/dev/null
    echo -e "${YELLOW}[INFO]${NC} Interface: $WIFI_IFACE"

    echo ""
    echo -e "${YELLOW}Redes disponibles:${NC}"
    scan_networks
    echo ""

    printf "SSID: "; read SSID
    printf "Password: "; read -s PSK
    echo ""

    [ -z "$SSID" ] && { echo -e "${RED}[ERROR]${NC} SSID required"; return 1; }

    connect_wpa "$SSID" "$PSK"
}

# --------------------------------------------------
# Main
# --------------------------------------------------
interactive "$@"
