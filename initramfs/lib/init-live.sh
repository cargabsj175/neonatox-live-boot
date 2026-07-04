# init-live.sh — live profile: overlay, device scan, ventoy, squashfs
PROFILE_NAME="live"
PROFILE_REQUIRES="mkfs.ext4 fsck.ext4 zstd btrfs mkfs.btrfs"

ISO_MNT="/mnt/iso"
ISO_TEST="/mnt/iso_test"
FOUND_DEV=""
VENTOY_MODE=0
FOUND_MATCH=0
OVERLAY_TYPE="tmpfs"

check_rootfs_hash() {
    if [ ! -f /rootfs.sha256 ]; then
        echo -e "${RED}[ERROR]${NC} rootfs.sha256 missing"
        return 1
    fi
    ROOTFS_HASH="$(cat /rootfs.sha256)"
}

setup_overlay() {
    if grep -q "zram=1" /proc/cmdline; then
        TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        if [ "$TOTAL_KB" -ge 262144 ]; then
            if [ "$TOTAL_KB" -lt 4194304 ]; then
                ZRAM_KB=$((TOTAL_KB * 1 / 3))
            else
                ZRAM_KB=$((TOTAL_KB / 2))
            fi
            [ "$ZRAM_KB" -gt 2097152 ] && ZRAM_KB=2097152
            echo -e "${YELLOW}[INFO]${NC} Configuring zram overlay (${ZRAM_KB} KB)"
            if modprobe zram num_devices=1 2>/dev/null; then
                if [ ! -b /dev/zram0 ]; then
                    read MAJOR MINOR < /sys/block/zram0/dev
                    mknod /dev/zram0 b "$MAJOR" "$MINOR"
                    chmod 600 /dev/zram0
                fi
                [ -e /sys/block/zram0/comp_algorithm ] && \
                    grep -q "\[lz4\]" /sys/block/zram0/comp_algorithm && echo lz4 > /sys/block/zram0/comp_algorithm
                if echo "$((ZRAM_KB * 1024))" > /sys/block/zram0/disksize && \
                    command -v mkfs.ext4 >/dev/null && mkfs.ext4 -q /dev/zram0 && \
                    FSTYPE="ext4" || \
                    (command -v mkfs.ext2 >/dev/null && mkfs.ext2 -q /dev/zram0 && FSTYPE="ext2") && \
                    mkdir -p /mnt/zram-overlay && \
                    mount /dev/zram0 /mnt/zram-overlay; then
                    mkdir -p /mnt/zram-overlay/upper /mnt/zram-overlay/work
                    OVERLAY_TYPE="zram"
                    echo -e "${GREEN}[OK]${NC} Zram overlay ready with ${FSTYPE}"
                fi
            fi
        fi
    fi
    if [ "$OVERLAY_TYPE" != "zram" ]; then
        echo -e "${YELLOW}[INFO]${NC} Using tmpfs fallback"
        mount -t tmpfs tmpfs /mnt/ram || {
            echo -e "${RED}[ERROR]${NC} tmpfs mount failed"
            return 1
        }
        mkdir -p /mnt/ram/upper /mnt/ram/work
    fi
}

detect_ventoy() {
    if [ -d /ventoy ] || [ -d /vtoy ]; then
        echo -e "${YELLOW}[INFO]${NC} Ventoy environment detected"
        VENTOY_MODE=1
    fi
}

scan_devices() {
    echo -e "${YELLOW}[INFO]${NC} scanning for boot media..."
    for attempt in 1 2 3; do
        echo -e "  ${YELLOW}[SCAN]${NC} attempt: $attempt/3"
        [ $attempt -eq 1 ] && sleep 1.5
        for host in /sys/class/scsi_host/host*; do
            echo "- - -" > "$host/scan" 2>/dev/null || true
        done
        sleep 1
        mdev -s
        for DEV in /dev/sr* /dev/nvme*n*p* /dev/nvme*n /dev/sd* /dev/hd* /dev/mmcblk*p* /dev/mmcblk*; do
            [ -e "$DEV" ] || continue
            echo -e "  ${YELLOW}[SCAN]${NC} device: $DEV"
            mount -o ro "$DEV" "$ISO_MNT" 2>/dev/null || continue
            if [ -f "$ISO_MNT/rootfs.squashfs" ]; then
                if [ ! -f "$ISO_MNT/rootfs.sha256" ]; then
                    echo -e "${RED}[ERROR]${NC} rootfs.sha256 missing in ISO"
                    umount "$ISO_MNT" 2>/dev/null; continue
                fi
                if echo "$CMDLINE" | grep -q "checkhash=1"; then
                    echo -e "${YELLOW}[INFO]${NC} full rootfs hash verification"
                    CALC="$(sha256sum "$ISO_MNT/rootfs.squashfs" | awk '{print $1}')"
                    if [ "$CALC" = "$ROOTFS_HASH" ]; then
                        echo -e "${GREEN}[OK]${NC} rootfs.squashfs hash verified (ISO)"
                        FOUND_MATCH=1
                    else
                        echo -e "${YELLOW}[WARN]${NC} rootfs hash mismatch (ISO)"
                        umount "$ISO_MNT" 2>/dev/null; continue
                    fi
                else
                    echo -e "${YELLOW}[INFO]${NC} fast hash check (file compare)"
                    if [ "$(cat "$ISO_MNT/rootfs.sha256")" = "$ROOTFS_HASH" ]; then
                        echo -e "${GREEN}[OK]${NC} rootfs.sha256 verified (ISO)"
                        FOUND_MATCH=1
                    else
                        echo -e "${YELLOW}[WARN]${NC} rootfs hash mismatch (ISO)"
                        umount "$ISO_MNT" 2>/dev/null; continue
                    fi
                fi
                FOUND_DEV="$DEV"; break 2
            fi
            ISO_LIST="$(ls "$ISO_MNT"/*.iso 2>/dev/null)"
            if [ "$VENTOY_MODE" = "1" ] && [ -n "$ISO_LIST" ]; then
                echo -e "${YELLOW}[INFO]${NC} ISO partition detected on $DEV"
                for ISO in "$ISO_MNT"/*.iso; do
                    echo -e "  ${YELLOW}[TESTING]${NC} ISO $(basename "$ISO")"
                    LOOP="$(losetup -f "$ISO" && losetup -a | grep "$ISO" | sed 's/:.*//')" || continue
                    mount -o ro "$LOOP" "$ISO_TEST" 2>/dev/null || { losetup -d "$LOOP"; continue; }
                    if [ -f "$ISO_TEST/rootfs.squashfs" ]; then
                        if [ ! -f "$ISO_TEST/rootfs.sha256" ]; then
                            echo -e "${RED}[ERROR]${NC} rootfs.sha256 missing in ISO"
                            umount "$ISO_TEST" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null; continue
                        fi
                        if echo "$CMDLINE" | grep -q "checkhash=1"; then
                            CALC="$(sha256sum "$ISO_TEST/rootfs.squashfs" | awk '{print $1}')"
                            if [ "$CALC" = "$ROOTFS_HASH" ]; then
                                echo -e "${GREEN}[OK]${NC} rootfs.squashfs hash verified (Ventoy)"
                                FOUND_MATCH=1
                            else
                                echo -e "${YELLOW}[WARN]${NC} rootfs hash mismatch (Ventoy)"
                                umount "$ISO_TEST" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null; continue
                            fi
                        else
                            if [ "$(cat "$ISO_TEST/rootfs.sha256")" = "$ROOTFS_HASH" ]; then
                                echo -e "${GREEN}[OK]${NC} rootfs.sha256 verified (Ventoy)"
                                FOUND_MATCH=1
                            else
                                echo -e "${YELLOW}[WARN]${NC} rootfs hash mismatch (Ventoy)"
                                umount "$ISO_TEST" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null; continue
                            fi
                        fi
                        FOUND_DEV="ventoy_iso"; ISO_MNT="$ISO_TEST"; break 3
                    fi
                    if [ "$FOUND_DEV" != "ventoy_iso" ]; then
                        umount "$ISO_TEST" 2>/dev/null
                        [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
                    fi
                done
            fi
            if [ "$FOUND_DEV" != "ventoy_iso" ]; then
                umount "$ISO_MNT" 2>/dev/null || umount -l "$ISO_MNT"
            fi
        done
    done
    if [ -z "$FOUND_DEV" ]; then
        echo -e "${RED}[ERROR]${NC} rootfs.squashfs not found"
        return 1
    fi
    echo -e "${GREEN}[OK]${NC} found boot media at $FOUND_DEV"
}

mount_squashfs() {
    mkdir -p /mnt/ro_root
    if [ "$FOUND_DEV" = "ventoy_iso" ]; then
        echo -e "${YELLOW}[INFO]${NC} mounting squashfs from Ventoy ISO"
        mount -t squashfs "$ISO_MNT/rootfs.squashfs" /mnt/ro_root || return 1
    else
        echo -e "${YELLOW}[INFO]${NC} mounting squashfs from physical media"
        mount -t squashfs -o loop "$ISO_MNT/rootfs.squashfs" /mnt/ro_root || return 1
    fi
    echo -e "${GREEN}[OK]${NC} squashfs mounted"
}

mount_overlay() {
    if [ "$OVERLAY_TYPE" = "zram" ]; then
        mount -t overlay overlay \
            -o lowerdir=/mnt/ro_root,upperdir=/mnt/zram-overlay/upper,workdir=/mnt/zram-overlay/work \
            /mnt/newroot || { echo -e "${RED}[ERROR]${NC} overlay on (${OVERLAY_TYPE}) mount failed"; return 1; }
    else
        mount -t overlay overlay \
            -o lowerdir=/mnt/ro_root,upperdir=/mnt/ram/upper,workdir=/mnt/ram/work \
            /mnt/newroot || { echo -e "${RED}[ERROR]${NC} overlay on (${OVERLAY_TYPE}) mount failed"; return 1; }
    fi
    echo -e "${GREEN}[OK]${NC} Overlay mounted on (${OVERLAY_TYPE})"
}

run_live_config() {
    if echo "$CMDLINE" | grep -q "neoconfig=1"; then
        echo -e "${YELLOW}[INFO]${NC} Running Live Setup..."
        if [ -x /live-config.sh ]; then
            /live-config.sh
        fi
    fi
}

setup_newroot() {
    mkdir -p /mnt/newroot/proc /mnt/newroot/sys /mnt/newroot/dev /mnt/newroot/run
    mount -t proc  proc  /mnt/newroot/proc
    mount -t sysfs sysfs /mnt/newroot/sys
    mount -t devtmpfs devtmpfs /mnt/newroot/dev
    mkdir -p /mnt/newroot/dev/pts
    mount -t devpts devpts -o gid=5,mode=0620 /mnt/newroot/dev/pts
    mount -t tmpfs tmpfs /mnt/newroot/run
    mkdir -p /mnt/newroot/mnt/iso /mnt/newroot/boot
    if [ "$VENTOY_MODE" = "1" ]; then
        mount --bind /mnt/iso_test /mnt/newroot/mnt/iso
        [ -d /mnt/iso_test/boot ] && mount --bind /mnt/iso_test/boot /mnt/newroot/boot
    else
        mount --bind /mnt/iso /mnt/newroot/mnt/iso
        [ -d /mnt/iso/boot ] && mount --bind /mnt/iso/boot /mnt/newroot/boot
    fi
    if [ -x /mnt/newroot/lib/systemd/systemd ]; then
        mkdir -p /mnt/newroot/etc
        [ -f /mnt/newroot/etc/machine-id ] || touch /mnt/newroot/etc/machine-id
    fi
    cat > /mnt/newroot/etc/fstab <<EOF
proc  /proc  proc  defaults  0 0
sysfs /sys   sysfs defaults  0 0
devpts /dev/pts devpts defaults  0 0
tmpfs /run   tmpfs defaults  0 0
EOF
    if [ -x /mnt/newroot/lib/systemd/systemd ]; then
        INIT="/lib/systemd/systemd"
    elif [ -x /mnt/newroot/sbin/init ]; then
        INIT="/sbin/init"
    else
        echo -e "${RED}[FATAL]${NC} no init found in new root"
        return 1
    fi
}
