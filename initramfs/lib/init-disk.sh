PROFILE_NAME="disk"
PROFILE_REQUIRES=""

root=
rootdelay=
rootfstype=auto
ro="ro"
rootflags=
device=
resume=
noresume=false
SPLASH=none
INIT=/sbin/init

parse_root_cmdline() {
    for param in $CMDLINE; do
        case $param in
            init=*)       INIT=${param#init=} ;;
            root=*)       root=${param#root=} ;;
            rootdelay=*)  rootdelay=${param#rootdelay=} ;;
            rootfstype=*) rootfstype=${param#rootfstype=} ;;
            rootflags=*)  rootflags=${param#rootflags=} ;;
            resume=*)     resume=${param#resume=} ;;
            noresume)     noresume=true ;;
            splash=*)     SPLASH=${param#splash=} ;;
            ro)           ro="ro" ;;
            rw)           ro="rw" ;;
        esac
    done
}

find_udevd() {
    if [ -x /sbin/udevd ]; then
        echo /sbin/udevd
    elif [ -x /lib/udev/udevd ]; then
        echo /lib/udev/udevd
    elif [ -x /lib/systemd/systemd-udevd ]; then
        echo /lib/systemd/systemd-udevd
    else
        return 1
    fi
}

setup_udev() {
    UDEVD=$(find_udevd) || {
        echo -e "${RED}[ERROR]${NC} udevd not found"
        return 1
    }
    echo -e "${YELLOW}[INFO]${NC} Starting udev..."
    $UDEVD --daemon --resolve-names=never
    udevadm trigger
    udevadm settle
    echo -e "${GREEN}[OK]${NC} udev ready"
}

splash_start() {
    case "$SPLASH" in
        none|""|no) return ;;
        plymouth)
            if [ -x /sbin/plymouthd ]; then
                /sbin/plymouthd --mode=boot --pid-file=/run/plymouthd.pid
                /sbin/plymouth show-splash
            fi ;;
    esac
}

splash_update() {
    case "$SPLASH" in
        none|""|no) return ;;
        plymouth)
            if [ -x /sbin/plymouth ]; then
                /sbin/plymouth update --progress="$1"
            fi ;;
    esac
}

splash_quit() {
    case "$SPLASH" in
        none|""|no) return ;;
        plymouth)
            if [ -x /sbin/plymouth ]; then
                /sbin/plymouth quit || killall plymouthd 2>/dev/null
            fi ;;
    esac
}

activate_raid() {
    if [ -f /etc/mdadm.conf ] && [ -x /sbin/mdadm ]; then
        mdadm -As 2>/dev/null || true
    fi
}

activate_lvm() {
    if [ -x /sbin/vgchange ]; then
        vgchange -a y >/dev/null 2>&1 || true
    fi
}

do_try_resume() {
    case "$resume" in
        UUID=*) eval "$resume"; resume="/dev/disk/by-uuid/$UUID" ;;
        LABEL=*) eval "$resume"; resume="/dev/disk/by-label/$LABEL" ;;
    esac
    if $noresume || ! [ -b "$resume" ]; then
        return
    fi
    local maj min
    ls -lH "$resume" | (read x x x x maj min x
        echo -n "${maj%,}:$min" > /sys/power/resume)
}

do_mount_root() {
    mkdir -p /.root
    [ -n "$rootflags" ] && rootflags="$rootflags,"
    rootflags="${rootflags}$ro"

    case "$root" in
        /dev/*)    device=$root ;;
        UUID=*)    eval "$root"; device="/dev/disk/by-uuid/$UUID" ;;
        PARTUUID=*) eval "$root"; device="/dev/disk/by-partuuid/$PARTUUID" ;;
        LABEL=*)   eval "$root"; device="/dev/disk/by-label/$LABEL" ;;
        "")        echo -e "${RED}[ERROR]${NC} No root device specified"; return 1 ;;
    esac

    local wait=0
    while [ ! -b "$device" ]; do
        if [ $wait -ge 30 ]; then
            echo -e "${RED}[ERROR]${NC} Root device $device not found after 30s"
            return 1
        fi
        sleep 1
        wait=$((wait + 1))
    done

    if ! mount -n -t "$rootfstype" -o "$rootflags" "$device" /.root; then
        echo -e "${RED}[ERROR]${NC} Could not mount $device"
        return 1
    fi
    echo -e "${GREEN}[OK]${NC} mounted $root on /.root"
}
