# init-net.sh — netinstall profile: DHCP, WiFi, NTP, Dropbear

show_ip() {
    echo ""
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${GREEN}   NET INSTALL - NEONATOX LIVE BOOT${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Network interfaces:${NC}"
    for iface in $(ip link | grep -o '^[0-9]*: [^:]*' | cut -d' ' -f2 | grep -v lo); do
        IP=$(ip -4 addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}')
        if [ -n "$IP" ]; then
            echo -e "  ${GREEN}$iface${NC}: $IP"
        else
            echo -e "  ${YELLOW}$iface${NC}: no DHCP"
        fi
    done
    echo ""
    echo -e "  ${YELLOW}SSH:${NC} ssh root@${IP%/*}"
    echo -e "  ${YELLOW}Pass:${NC} neonatox"
}

show_guide() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   NEONATOX NET INSTALL - QUICK GUIDE${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo ""
    echo " 1. Prepare target disk:"
    echo "      fdisk /dev/sda            (partition)"
    echo "      mkfs.ext4 /dev/sda1       (format)"
    echo "      mount /dev/sda1 /mnt      (mount)"
    echo " 2. Run base installer:"
    echo "      neonatox-bootstrap -L /mnt core"
    echo " 3. (Optional) Install desktop:"
    echo "      neonatox-bootstrap -L /mnt -p mypassword xfce"
    echo ""
    echo -e " ${YELLOW}Docs:${NC} https://github.com/cargabsj175/neonatox-bootstrap"
    echo ""
    echo -e "${YELLOW}[INFO]${NC} WiFi: only ath5k/ath9k without firmware included"
    echo -e "${YELLOW}[INFO]${NC} For other chipsets, load modules manually after install"
    echo ""
}

dhcp_all() {
    echo -e "${YELLOW}[INFO]${NC} Bringing up network (DHCP)..."
    for iface in $(ip link | grep -o '^[0-9]*: [^:]*' | cut -d' ' -f2 | grep -v lo); do
        ip link set "$iface" up
        sleep 2
        udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -t 5 -T 2 2>/dev/null || true
        if ip -4 addr show "$iface" | grep -q 'inet '; then
            echo -e "  ${GREEN}[OK]${NC} $iface has IP"
        else
            echo -e "  ${RED}[FAIL]${NC} $iface no DHCP lease"
        fi
    done
}

wifi_config() {
    HAS_DHCP="$(ip -4 addr | grep 'inet ' | grep -v 127.0.0.1 | head -1)"
    if [ -z "$HAS_DHCP" ] && [ -x /wifi-config.sh ]; then
        echo -e "${YELLOW}[INFO]${NC} No DHCP via cable, starting WiFi config..."
        /wifi-config.sh
    fi
}

ntp_sync() {
    HAS_IP="$(ip -4 addr | grep 'inet ' | grep -v 127.0.0.1 | head -1)"
    if [ -n "$HAS_IP" ]; then
        echo -e "${YELLOW}[INFO]${NC} Setting time via NTP..."
        ntpd -n -q -p pool.ntp.org 2>/dev/null && echo -e "${GREEN}[OK]${NC} time synced" || \
            echo -e "${YELLOW}[WARN]${NC} NTP sync failed (non-fatal)"
    fi
}

setup_ssh() {
    mkdir -p /etc
    echo "root:x:0:0:root:/root:/bin/sh" > /etc/passwd
    ROOT_HASH="$(printf '%s' 'neonatox' | cryptpw -m sha512)"
    echo "root:$ROOT_HASH:1:0:99999:7:::" > /etc/shadow
    echo -e "${GREEN}[OK]${NC} root password: neonatox"
    echo -e "${YELLOW}[INFO]${NC} Generating dropbear host keys..."
    mkdir -p /etc/dropbear
    if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ]; then
        dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key > /dev/null 2>&1
    fi
    if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
        dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key > /dev/null 2>&1
    fi
    dropbear 2>/dev/null && echo -e "${GREEN}[OK]${NC} dropbear running" || \
        echo -e "${RED}[ERROR]${NC} dropbear failed to start"
}
