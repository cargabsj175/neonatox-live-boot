#!/bin/busybox sh
# /live-config.sh
# Neonatox Live Boot Configuration
# Language, keyboard, time zone, and Live user

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
    echo -e "${GREEN}3.${NC} Português - Brasil" > /dev/tty1
    echo -e "${GREEN}4.${NC} Português - Portugal" > /dev/tty1
    echo -e "${GREEN}5.${NC} Français - France" > /dev/tty1
    echo -e "${GREEN}6.${NC} Русский - Россия" > /dev/tty1
    echo "" > /dev/tty1
    echo -e "    ${YELLOW}Select an option (timeout 60s):${NC} [1]" > /dev/tty1

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
                LANG="pt_PT.UTF-8"
                TZ="Europe/Lisbon"
                KEYMAP="pt"
                ;;
            5)
                LANG="fr_FR.UTF-8"
                TZ="Europe/Paris"
                KEYMAP="fr"
                ;;
            6)
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
    echo -e "${BLUE}[Live]${NC} Applying settings..."

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
    # Passwordless sudo
    # --------------------------------------------------
    mkdir -p "$NEWROOT/etc/sudoers.d"
    cat > "$NEWROOT/etc/sudoers.d/99-live" <<EOF
$LIVE_USER ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 "$NEWROOT/etc/sudoers.d/99-live" 2>/dev/null || true

    # --------------------------------------------------
    # Autologin tty1
    # --------------------------------------------------
    mkdir -p "$NEWROOT/etc/systemd/system/getty@tty1.service.d"
    cat > "$NEWROOT/etc/systemd/system/getty@tty1.service.d/override.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $LIVE_USER --noclear --keep-baud %I \$TERM
EOF

    # --------------------------------------------------
    # User startup files
    # --------------------------------------------------
    cp -a "$NEWROOT/etc/skel/." "$NEWROOT/home/$LIVE_USER/"

    cat > "$NEWROOT/home/$LIVE_USER/.xinitrc" <<'EOF'
#!/bin/sh
exec startxfce4
EOF
    chmod 755 "$NEWROOT/home/$LIVE_USER/.xinitrc"

    cat > "$NEWROOT/home/$LIVE_USER/.bash_profile" <<'EOF'
# Load bashrc if exists
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

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
    echo -e "    ${YELLOW}Time zone:${NC} $TZ"
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
