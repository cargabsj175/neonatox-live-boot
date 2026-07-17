#!/bin/sh
# NeonatoX WiFi Wizard
# Interactive WiFi setup for netinstall & live modes
# Uses: wpa_supplicant, wpa_cli, wpa_passphrase, dhcpcd|udhcpc
# No iw dependency — scanning via wpa_cli

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

WPA_CONF="/tmp/wpa_supplicant.conf"
WPA_CTRL="/var/run/wpa_supplicant"

if command -v dhcpcd >/dev/null 2>&1; then
    DHCP_CLIENT="dhcpcd"
else
    DHCP_CLIENT="udhcpc"
fi

# --- helpers ----------------------------------------------------------------

die()    { echo -e "${RED}${1}${NC}"; exit 1; }
warn()   { echo -e "${YELLOW}${1}${NC}"; }
ok()     { echo -e "${GREEN}${1}${NC}"; }
info()   { echo -e "${BLUE}${1}${NC}"; }

check_deps() {
    local miss=""
    for cmd in wpa_supplicant wpa_cli wpa_passphrase "$DHCP_CLIENT"; do
        command -v "$cmd" >/dev/null 2>&1 || miss="$miss $cmd"
    done
    [ -n "$miss" ] && die "Missing:${miss}"
}

ensure_udhcpc_script() {
    local script="/usr/share/udhcpc/default.script"
    [ -f "$script" ] && return 0
    mkdir -p "${script%/*}"
    cat > "$script" << 'UDHCPC'
#!/bin/sh
case "$1" in
    deconfig)
        ip addr flush dev "$interface" 2>/dev/null
        ip link set "$interface" up 2>/dev/null
        ;;
    bound|renew)
        ip addr add "$ip/${mask:-24}" dev "$interface"
        [ -n "$router" ] && for r in $router; do
            ip route add default via "$r" dev "$interface" 2>/dev/null || true
        done
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        ;;
    nak)
        ip addr flush dev "$interface" 2>/dev/null
        ;;
esac
UDHCPC
    chmod 0755 "$script"
}

dhcp_run() {
    local iface="$1"
    case "$DHCP_CLIENT" in
        dhcpcd)
            dhcpcd -1 -t 20 "$iface" 2>/dev/null
            sleep 2
            ;;
        udhcpc)
            udhcpc -i "$iface" -q -t 10 -T 2 2>/dev/null
            sleep 2
            ;;
    esac
}

find_ifaces() {
    local found=0
    for iface in /sys/class/net/*; do
        [ -d "$iface/wireless" ] || continue
        echo "${iface##*/}"
        found=1
    done
    [ "$found" = 0 ] && return 1
    return 0
}

iface_has_ip() {
    ip -4 addr show "$1" 2>/dev/null | grep -q 'inet '
}

wpa_stop() {
    wpa_cli -i "$1" terminate 2>/dev/null || true
    killall wpa_supplicant 2>/dev/null || true
    sleep 1
}

wpa_start() {
    local iface="$1"
    mkdir -p "$WPA_CTRL"
    cat > "$WPA_CONF" <<-EOF
		ctrl_interface=$WPA_CTRL
		update_config=1
	EOF
    wpa_supplicant -B -i "$iface" -c "$WPA_CONF" >/dev/null 2>&1 || return 1
    local wait=0
    while [ ! -S "$WPA_CTRL/$iface" ] && [ "$wait" -lt 10 ]; do
        sleep 1; wait=$((wait + 1))
    done
    [ -S "$WPA_CTRL/$iface" ]
}

wpa_scan() {
    local iface="$1"
    # Send scan; show output to user
    wpa_cli -i "$iface" scan 2>&1
    # Wait progressively with dots
    local waited=0
    while [ "$waited" -lt 7 ]; do
        echo -n "." >&2
        sleep 1
        waited=$((waited + 1))
    done
    echo "" >&2
    # Only output lines that start with a BSSID (MAC)
    wpa_cli -i "$iface" scan_results 2>/dev/null | grep -E '^[0-9a-f]{2}(:[0-9a-f]{2}){5}[[:space:]]'
}

# --- modes ------------------------------------------------------------------

cmd_scan() {
    local iface="${1:-}"
    check_deps
    if [ -z "$iface" ]; then
        ifaces=$(find_ifaces) || die "No WiFi interfaces found"
        iface=$(echo "$ifaces" | head -1)
    fi
    info "Interface: $iface"
    ip link set "$iface" up 2>/dev/null || true

    wpa_stop "$iface"
    wpa_start "$iface" || die "Failed to start wpa_supplicant"
    echo -e "  ${YELLOW}Scanning (7s)${NC}"
    wpa_scan "$iface" | while IFS=$'\t' read -r bssid freq sig flags ssid; do
        echo "$sig dBm  $ssid"
    done
    echo -e "  ${GREEN}Done${NC}"
    wpa_stop "$iface"
}

cmd_connect() {
    local iface="${3:-}"
    local ssid="$1" psk="$2"
    [ -z "$ssid" ] && die "Usage: wifi-wizard --connect SSID PSK [IFACE]"

    check_deps
    [ "$DHCP_CLIENT" = "udhcpc" ] && ensure_udhcpc_script
    [ -z "$iface" ] && {
        ifaces=$(find_ifaces) || die "No WiFi interfaces found"
        iface=$(echo "$ifaces" | head -1)
    }
    info "Interface: $iface"
    ip link set "$iface" up 2>/dev/null || true

    wpa_stop "$iface"
    echo -e "${YELLOW}Connecting to $ssid...${NC}"
    wpa_passphrase "$ssid" "$psk" > "$WPA_CONF" 2>/dev/null
    cat >> "$WPA_CONF" <<-EOF
		ctrl_interface=$WPA_CTRL
		update_config=1
	EOF
    wpa_supplicant -B -i "$iface" -c "$WPA_CONF" >/dev/null 2>&1 || die "wpa_supplicant failed"

    local waited=0
    while [ "$waited" -lt 20 ]; do
        if iface_has_ip "$iface"; then
            ok "Connected: $ssid ($(ip -4 addr show "$iface" | grep 'inet ' | awk '{print $2}'))"
            return 0
        fi
        sleep 1; waited=$((waited + 1))
    done
    warn "Associated but no IP — running DHCP..."
    dhcp_run "$iface"
    if iface_has_ip "$iface"; then
        ok "Connected: $ssid ($(ip -4 addr show "$iface" | grep 'inet ' | awk '{print $2}'))"
        return 0
    fi
    die "Failed to get IP on $ssid"
}

cmd_interactive() {
    check_deps
    [ "$DHCP_CLIENT" = "udhcpc" ] && ensure_udhcpc_script

    # --- Find interface ---
    ifaces=$(find_ifaces) || die "No WiFi interfaces found"
    local iface_count=0
    for _ in $ifaces; do iface_count=$((iface_count + 1)); done

    local iface=""
    if [ "$iface_count" -gt 1 ]; then
        echo ""
        info "Available WiFi interfaces:"
        local i=1
        for f in $ifaces; do
            echo "  $i) $f"
            i=$((i + 1))
        done
        while :; do
            read -r -p "Select interface (1-$iface_count): " n || exit 1
            case "$n" in
                ''|*[!0-9]*) continue ;;
            esac
            [ "$n" -ge 1 ] && [ "$n" -le "$iface_count" ] || continue
            local j=1
            for f in $ifaces; do
                [ "$j" -eq "$n" ] && { iface="$f"; break; }
                j=$((j + 1))
            done
            break
        done
    else
        iface="$ifaces"
    fi
    info "Interface: $iface"
    ip link set "$iface" up 2>/dev/null || true

    # --- Start wpa_supplicant ---
    wpa_stop "$iface"
    wpa_start "$iface" || die "Failed to start wpa_supplicant"

    # --- Scan ---
    echo -e "  ${YELLOW}Scanning (7s)${NC}"
    # Collect unique SSIDs (one per line, skip duplicates)
    local ssids
    ssids=$(wpa_scan "$iface" | while IFS=$'\t' read -r bssid freq sig flags ssid; do
        [ -z "$ssid" ] && continue
        echo "$ssid"
    done | sort -u)
    local ssid_count=0
    [ -n "$ssids" ] && for _ in $ssids; do ssid_count=$((ssid_count + 1)); done

    [ "$ssid_count" -eq 0 ] && { wpa_stop "$iface"; die "No networks found (try again later)"; }

    echo ""
    info "Available networks:"
    local i=1
    for s in $ssids; do
        echo "  $i) $s"
        i=$((i + 1))
    done

    local chosen
    while :; do
        read -r -p "Select network (1-$ssid_count): " chosen || { wpa_stop "$iface"; exit 1; }
        case "$chosen" in
            ''|*[!0-9]*) continue ;;
        esac
        [ "$chosen" -ge 1 ] && [ "$chosen" -le "$ssid_count" ] && break
    done

    local target_ssid="" j=1
    for s in $ssids; do
        [ "$j" -eq "$chosen" ] && { target_ssid="$s"; break; }
        j=$((j + 1))
    done

    # --- Password ---
    echo ""
    read -r -p "Password for \"$target_ssid\": " psk
    [ -z "$psk" ] && { wpa_stop "$iface"; die "Password required"; }

    # --- Connect ---
    wpa_stop "$iface"
    echo -e "${YELLOW}Connecting...${NC}"
    wpa_passphrase "$target_ssid" "$psk" > "$WPA_CONF" 2>/dev/null
    cat >> "$WPA_CONF" <<-EOF
		ctrl_interface=$WPA_CTRL
		update_config=1
	EOF
    wpa_supplicant -B -i "$iface" -c "$WPA_CONF" >/dev/null 2>&1 || die "wpa_supplicant failed"

    local waited=0
    while [ "$waited" -lt 15 ]; do
        iface_has_ip "$iface" && break
        sleep 1; waited=$((waited + 1))
    done

    if iface_has_ip "$iface"; then
        ok "Connected: $target_ssid ($(ip -4 addr show "$iface" | grep 'inet ' | awk '{print $2}'))"
    else
        info "Running DHCP..."
        dhcp_run "$iface"
        if iface_has_ip "$iface"; then
            ok "Connected: $target_ssid ($(ip -4 addr show "$iface" | grep 'inet ' | awk '{print $2}'))"
        else
            warn "Associated but no IP. Check password or try manual: ${DHCP_CLIENT} -i $iface"
        fi
    fi
}

# --- main -------------------------------------------------------------------

case "${1:-}" in
    -h|--help)
        echo "NeonatoX WiFi Wizard"
        echo ""
        echo "  wifi-wizard                  Interactive WiFi setup"
        echo "  wifi-wizard --scan [IFACE]   Scan and show networks"
        echo "  wifi-wizard --connect SSID PSK [IFACE]   Auto-connect"
        echo "  wifi-wizard --help           This help"
        ;;
    --scan)
        shift; cmd_scan "$@"
        ;;
    --connect)
        shift; cmd_connect "$@"
        ;;
    "")
        cmd_interactive
        ;;
    *)
        die "Unknown option: $1 (use --help)"
        ;;
esac
