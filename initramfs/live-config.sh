#!/bin/busybox sh
# /live-config.sh
# Neonatox Live Boot Configuration
# Language, keyboard, time zone and live user

# --------------------------------------------------
# Colors (TTY safe)
# --------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --------------------------------------------------
# Fixed variables
# --------------------------------------------------
LIVE_USER="neonatox"
LIVE_USER_PASS="neonatox"
LIVE_UID=999
NEWROOT="/mnt/newroot"

# --------------------------------------------------
# Default configurable values
# --------------------------------------------------
LANG="es_VE.UTF-8"
TZ="America/Caracas"
KEYMAP="es"

# --------------------------------------------------
# Interactive menu (optional, timeout safe)
# --------------------------------------------------
show_menu() {
    [ -c /dev/tty1 ] || return 0

    stty sane < /dev/tty1

    echo "" > /dev/tty1
    clear
    echo -e "${BLUE}═════════════════════════════════════════${NC}" > /dev/tty1
    echo -e "${GREEN}   NEONATOX LIVE BOOT CONFIGURATION${NC}" > /dev/tty1
    echo -e "${BLUE}═════════════════════════════════════════${NC}" > /dev/tty1
    echo "" > /dev/tty1

    echo -e "    ${YELLOW}Usuario:${NC} $LIVE_USER (fijo)" > /dev/tty1
    echo "" > /dev/tty1

    echo -e "${GREEN}1.${NC} Español - Venezuela [Enter]" > /dev/tty1
    echo -e "${GREEN}2.${NC} English - USA" > /dev/tty1
    echo -e "${GREEN}3.${NC} Português - Brasil - TZ Sao Paulo" > /dev/tty1
    echo -e "${GREEN}4.${NC} Português - Brasil - TZ Manaus" > /dev/tty1
    echo -e "${GREEN}5.${NC} Português - Portugal" > /dev/tty1
    echo -e "${GREEN}6.${NC} Français - France" > /dev/tty1
    echo -e "${GREEN}7.${NC} Русский - Россия" > /dev/tty1
    echo "" > /dev/tty1
    echo -e "    ${YELLOW}Seleccione una opción (timeout 60s):${NC} [1]" > /dev/tty1

    if read -t 60 choice < /dev/tty1; then
        case "$choice" in
            2)
                LANG="en_US.UTF-8"
                TZ="America/New_York"
                KEYMAP="us"
                ;;
            3)
                LANG="pt_BR.UTF-8"
                TZ="America/Sao_Paulo"
                KEYMAP="br"
                ;;
            4)
                LANG="pt_BR.UTF-8"
                TZ="America/Manaus"
                KEYMAP="br"
                ;;
            5)
                LANG="pt_PT.UTF-8"
                TZ="Europe/Lisbon"
                KEYMAP="pt"
                ;;
            6)
                LANG="fr_FR.UTF-8"
                TZ="Europe/Paris"
                KEYMAP="fr"
                ;;
            7)
                LANG="ru_RU.UTF-8"
                TZ="Europe/Moscow"
                KEYMAP="ru"
                ;;
            *)
                LANG="es_VE.UTF-8"
                TZ="America/Caracas"
                KEYMAP="es"
                ;;
        esac
    fi

    echo "" > /dev/tty1
    echo -e "${GREEN}[OK] Selected language:${NC} $LANG" > /dev/tty1
    sleep 2
}

# --------------------------------------------------
# Apply configuration to new root
# --------------------------------------------------
apply_config() {
    echo -e "${BLUE}[Live]${NC} Applying configuration..."

    mkdir -p "$NEWROOT/etc"

    # --------------------------------------------------
    # Locale
    # --------------------------------------------------
    echo "LANG=$LANG" > "$NEWROOT/etc/locale.conf"

    # --------------------------------------------------
    # Timezone
    # --------------------------------------------------
    if [ -f "$NEWROOT/usr/share/zoneinfo/$TZ" ]; then
        ln -sf "../usr/share/zoneinfo/$TZ" "$NEWROOT/etc/localtime" 2>/dev/null || true
        echo "$TZ" > "$NEWROOT/etc/timezone" 2>/dev/null || true
    fi

    # --------------------------------------------------
    # Console keymap
    # --------------------------------------------------
    if [ -d "$NEWROOT/usr/share/kbd/keymaps" ]; then
        echo "KEYMAP=$KEYMAP" > "$NEWROOT/etc/vconsole.conf"
    else
        rm -f "$NEWROOT/etc/vconsole.conf"
    fi

    # --------------------------------------------------
    # X11 keyboard (if exists)
    # --------------------------------------------------
    if [ -d "$NEWROOT/etc/X11/xorg.conf.d" ]; then
        cat > "$NEWROOT/etc/X11/xorg.conf.d/00-keyboard.conf" <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$KEYMAP"
    Option "XkbModel" "pc105"
EndSection
EOF
    fi

    # --------------------------------------------------
    # Live user (fixed)
    # --------------------------------------------------
    mkdir -p "$NEWROOT/home/$LIVE_USER"

    SHELL="/bin/sh"
    [ -x "$NEWROOT/bin/bash" ] && SHELL="/bin/bash"

    grep -q "^$LIVE_USER:" "$NEWROOT/etc/passwd" 2>/dev/null || \
        echo "$LIVE_USER:x:$LIVE_UID:$LIVE_UID:NeonatoX Live:/home/$LIVE_USER:$SHELL" \
        >> "$NEWROOT/etc/passwd"

    # LIVE_USER_PASS
	if [ -z "$LIVE_USER_PASS" ]; then
        PASS_HASH="$(cryptpw -m sha512 '')"
    else
        PASS_HASH="$(printf '%s' "$LIVE_USER_PASS" | cryptpw -m sha512)"
    fi

    if grep -q "^$LIVE_USER:" "$NEWROOT/etc/shadow" 2>/dev/null; then
        sed -i "s|^$LIVE_USER:[^:]*:|$LIVE_USER:$PASS_HASH:|" \
            "$NEWROOT/etc/shadow"
    else
        echo "$LIVE_USER:$PASS_HASH:1:0:99999:7:::" \
            >> "$NEWROOT/etc/shadow"
    fi

    grep -q "^$LIVE_USER:" "$NEWROOT/etc/group" 2>/dev/null || \
        echo "$LIVE_USER:x:$LIVE_UID:" \
        >> "$NEWROOT/etc/group"
        
    # --------------------------------------------------
    # Add live user to common groups
    # --------------------------------------------------
    add_user_to_group() {
    group="$1"

    # group must exist
    grep -q "^$group:" "$NEWROOT/etc/group" || return 0

    # already member?
    grep "^$group:" "$NEWROOT/etc/group" | grep -q "$LIVE_USER" && return 0

    # append user to group
    sed -i "s/^$group:[^:]*:[^:]*:/&$LIVE_USER,/" "$NEWROOT/etc/group"
    }

    for g in adm video wheel seat input; do
       add_user_to_group "$g"
    done

# --------------------------------------------------
# Passwordless sudo/doas
# --------------------------------------------------

# sudo
[ -x "$NEWROOT/usr/bin/sudo" ] && {
    mkdir -p "$NEWROOT/etc/sudoers.d"
    echo "$LIVE_USER ALL=(ALL) NOPASSWD: ALL" > "$NEWROOT/etc/sudoers.d/99-live"
    chmod 440 "$NEWROOT/etc/sudoers.d/99-live" 2>/dev/null
}

# doas
[ -x "$NEWROOT/usr/bin/doas" ] && {
    mkdir -p "$NEWROOT/etc/doas.d"
    echo "permit nopass $LIVE_USER as root" > "$NEWROOT/etc/doas.d/99-live.conf"
    chmod 0400 "$NEWROOT/etc/doas.d/99-live.conf" 2>/dev/null
}


# --------------------------------------------------
# Autologin tty1 and disable screen managers
# --------------------------------------------------

# Function to disable screen managers
disable_display_managers() {
    echo "Disabling screen managers (if any are active)..."
    
    # Find and remove links to screen manager services
    for manager in gdm lightdm lxdm sddm xdm; do
        # Search in all common runlevel directories
        for dir in "$NEWROOT/etc/rc.d" \
                   "$NEWROOT/etc/rc0.d" "$NEWROOT/etc/rc1.d" "$NEWROOT/etc/rc2.d" \
                   "$NEWROOT/etc/rc3.d" "$NEWROOT/etc/rc4.d" "$NEWROOT/etc/rc5.d" \
                   "$NEWROOT/etc/rc6.d" "$NEWROOT/etc/rcS.d" \
                   "$NEWROOT/etc/runlevels"; do
            
            if [ -d "$dir" ]; then
                find "$dir" -name "*$manager*" -type l -delete 2>/dev/null
            fi
        done
    done
}

# Configure autologin according to the system
if [ -x "$NEWROOT/bin/systemctl" ] || [ -d "$NEWROOT/usr/lib/systemd" ]; then
    # Systemd
    mkdir -p "$NEWROOT/etc/systemd/system/getty@tty1.service.d"
    cat > "$NEWROOT/etc/systemd/system/getty@tty1.service.d/override.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $LIVE_USER --noclear --keep-baud %I \$TERM
EOF
    echo "Autologin configured for systemd"

elif [ -f "$NEWROOT/etc/inittab" ]; then
    # SysVinit/OpenRC
    disable_display_managers
    
    # Backup and modify inittab
    cp -f "$NEWROOT/etc/inittab" "$NEWROOT/etc/inittab.bak" 2>/dev/null
    sed -i '/^tty1::/d' "$NEWROOT/etc/inittab"
    echo "tty1::respawn:/bin/login -f $LIVE_USER" \
        >> "$NEWROOT/etc/inittab"
    echo "Autologin configured in inittab and managers disabled"
fi

    # --------------------------------------------------
    # User startup files
    # --------------------------------------------------
    
    # Copiying skel if exists
    cp -a "$NEWROOT/etc/skel/." "$NEWROOT/home/$LIVE_USER/" || true

    cat > "$NEWROOT/home/$LIVE_USER/.xinitrc" <<'EOF'
#!/bin/sh

# Load bashrc & profile if exists
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && . "$HOME/.profile"

exec startxfce4
EOF
    chmod 755 "$NEWROOT/home/$LIVE_USER/.xinitrc"
    
        cat > "$NEWROOT/home/$LIVE_USER/.profile" <<EOF
export LANG=$LANG
export LC_ALL=$LANG
EOF
    chmod 755 "$NEWROOT/home/$LIVE_USER/.profile"

    cat > "$NEWROOT/home/$LIVE_USER/.bash_profile" <<'EOF'
# Load bashrc & profile if exists
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && . "$HOME/.profile"

    exec startx
EOF

    # --------------------------------------------------
    # tmpfiles for permissions
    # --------------------------------------------------
    mkdir -p "$NEWROOT/etc/tmpfiles.d"
    cat > "$NEWROOT/etc/tmpfiles.d/live-user.conf" <<EOF
d /home/$LIVE_USER 0750 $LIVE_USER $LIVE_USER -
d /home/$LIVE_USER/.config 0750 $LIVE_USER $LIVE_USER -
d /home/$LIVE_USER/.cache 0750 $LIVE_USER $LIVE_USER -
d /home/$LIVE_USER/.local 0750 $LIVE_USER $LIVE_USER -
EOF

    # Ownership (important)
    chown -R $LIVE_UID:$LIVE_UID "$NEWROOT/home/$LIVE_USER" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}[Live] Configuration applied successfully:${NC}"
    echo -e "    ${YELLOW}User:${NC} $LIVE_USER"
    echo -e "    ${YELLOW}Language:${NC} $LANG"
    echo -e "    ${YELLOW}Timezone:${NC} $TZ"
    echo -e "    ${YELLOW}Keyboard:${NC} $KEYMAP"
}

# --------------------------------------------------
# Main
# --------------------------------------------------
main() {
    show_menu
    apply_config
    clear 2>/dev/null || echo ""
}

main "$@"
