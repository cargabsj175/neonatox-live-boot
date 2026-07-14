#!/bin/sh
# NeonatoX Disk Partitioning Wizard
# Guided partitioning for netinstall shell (busybox ash)
# Uses: fdisk, mkfs.ext4, mkswap, blkid, blockdev
# MBR or GPT (busybox fdisk with CONFIG_FEATURE_GPT_LABEL=y)
# Exports: DISK, ROOT_PART, SWAP_PART, MOUNT_POINT for nhopkg

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

STEP=0
DISK=""
ROOT_SIZE=""
SWAP="n"
SWAP_SIZE=""
ROOT_PART=""
SWAP_PART=""
EFI_PART=""
MOUNT_POINT="/mnt"
ABORTED=0
GPT=0
EFI=0
PARTTABLE="dos"

die() {
    echo -e "${RED}${1:-Aborted}${NC}"
    exit 1
}

step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "${BLUE}=== Step $STEP:${NC} $1"
}

select_yesno() {
    local prompt="$1 [y/N] "
    local REPLY
    while :; do
        read -r -p "$prompt" REPLY || return 1
        case "$REPLY" in
            y|Y) return 0 ;;
            n|N|"") return 1 ;;
            *) echo -e "${YELLOW}Enter 'y' or 'n'${NC}" ;;
        esac
    done
}

list_disks() {
    local first=1
    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        d="${dev##*/}"
        case "$d" in
            loop*|ram*|zram*|fd*) continue ;;
        esac
        [ -b "/dev/$d" ] || continue
        [ "$first" = 1 ] && first=0
        echo "/dev/$d"
    done
}

disk_size_str() {
    LC_ALL=C fdisk -l "$1" 2>/dev/null | head -1 | sed 's/Disk.*: //;s/, [0-9]* bytes.*//'
}

disk_bytes() {
    LC_ALL=C fdisk -l "$1" 2>/dev/null | head -1 | grep -oE '[0-9]+ bytes' | awk '{print $1}'
}

partitions_on() {
    LC_ALL=C fdisk -l "$1" 2>/dev/null | tail -n +6 | grep -E '^/dev' | awk '{print $1}'
}

select_disk() {
    local disks="" d i=1 chosen
    echo -e "${YELLOW}Scanning disks...${NC}"
    sleep 1
    for d in $(list_disks); do
        local size
        size=$(disk_size_str "$d")
        echo "  $i) $d  ($size)"
        disks="$disks $d"
        i=$((i + 1))
    done
    [ $i -eq 1 ] && die "No disks found!"
    echo "  q) Quit"
    echo ""
    while :; do
        read -r -p "Select disk (1-$((i - 1))): " chosen || die
        [ "$chosen" = "q" ] && die "Cancelled"
        case "$chosen" in
            ''|*[!0-9]*) continue ;;
        esac
        [ "$chosen" -ge 1 ] && [ "$chosen" -lt "$i" ] || continue
        DISK=""
        for d in $disks; do
            DISK="$d"
            chosen=$((chosen - 1))
            [ "$chosen" -eq 0 ] && break
        done
        break
    done
    echo -e "  ${GREEN}Selected: $DISK${NC}"
}

# Detect if fdisk supports GPT (g command)
detect_gpt() {
    local tmp
    tmp=$(mktemp /tmp/disk_test.XXXXXX 2>/dev/null) || return 1
    dd if=/dev/zero of="$tmp" bs=1M count=1 2>/dev/null
    echo "g" | fdisk "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return $rc
}

select_table_type() {
    if detect_gpt; then
        echo ""
        echo "Partition table types:"
        echo "  1) MBR (DOS) — legacy/compatible"
        echo "  2) GPT — modern, UEFI, >2TB"
        local tbl_choice
        read -r -p "Select type (1-2) [1]: " tbl_choice
        case "$tbl_choice" in
            2) GPT=1; PARTTABLE="gpt" ;;
            *) GPT=0; PARTTABLE="dos" ;;
        esac
    else
        echo -e "${YELLOW}[INFO]${NC} fdisk doesn't support GPT creation, using MBR"
        GPT=0
        PARTTABLE="dos"
    fi
    if [ "$GPT" = 1 ]; then
        echo -e "  Partition table: ${BLUE}GPT${NC}"
        if select_yesno "Create EFI System Partition (for UEFI boot)?"; then
            EFI=1
            echo -e "  ${BLUE}EFI partition will be created${NC}"
        fi
    else
        echo -e "  Partition table: ${BLUE}MBR (DOS)${NC}"
    fi
}

confirm_partition_table() {
    local existing
    existing=$(partitions_on "$DISK")
    if [ -n "$existing" ]; then
        echo ""
        echo -e "${YELLOW}Existing partitions on $DISK:${NC}"
        LC_ALL=C fdisk -l "$DISK" 2>/dev/null
        echo ""
        echo -e "${RED}WARNING: All data on $DISK will be DESTROYED!${NC}"
    fi
    echo -e "  This will ${RED}ERASE${NC} $DISK and create a new partition table."
    echo -e "  Type ${RED}YES${NC} (uppercase) to confirm: "
    local confirm
    read -r confirm || die
    [ "$confirm" = "YES" ] || die "Confirmation failed"
}

run_fdisk() {
    local script="$1"
    printf "%b" "$script" | fdisk "$DISK" >/dev/null 2>&1
    sleep 1
}

wait_for_part() {
    local part="$1" tries=10
    while [ $tries -gt 0 ]; do
        [ -b "$part" ] && return 0
        sleep 1
        tries=$((tries - 1))
    done
    return 1
}

do_auto() {
    local script disk_mb root_part_size next=1

    step "Partition scheme"
    echo "  Auto: single ext4 root + optional swap${EFI:+ + EFI System}"
    echo ""
    select_yesno "Create swap partition?" && SWAP="y" || SWAP="n"

    script=""
    # Partition table type
    [ "$GPT" = 1 ] && script="${script}g\n" || script="${script}o\n"

    # EFI System Partition (GPT only)
    if [ "$EFI" = 1 ]; then
        script="${script}n\n${next}\n\n+512M\n"
        script="${script}t\n${next}\n1\n"
        next=$((next + 1))
    fi

    # Root partition
    if [ "$SWAP" = "y" ] || [ -n "$ROOT_SIZE" ]; then
        if [ "$GPT" = 1 ]; then
            script="${script}n\n${next}\n\n${ROOT_SIZE:++${ROOT_SIZE}}\n"
        else
            script="${script}n\np\n${next}\n\n${ROOT_SIZE:++${ROOT_SIZE}}\n"
        fi
        next=$((next + 1))
    else
        # Single root takes all
        if [ "$GPT" = 1 ]; then
            script="${script}n\n${next}\n\n\n"
        else
            script="${script}n\np\n${next}\n\n\n"
        fi
        next=$((next + 1))
    fi

    # Swap partition
    if [ "$SWAP" = "y" ]; then
        disk_mb=$(($(disk_bytes "$DISK") / 1048576))
        local swap_default=$(( disk_mb / 10 ))
        [ "$swap_default" -gt 8192 ] && swap_default=8192
        [ "$swap_default" -lt 512 ] && swap_default=512
        swap_default="${swap_default}M"
        read -r -p "  Swap size (default ${swap_default}): " SWAP_SIZE
        [ -z "$SWAP_SIZE" ] && SWAP_SIZE="$swap_default"
        if [ "$GPT" = 1 ]; then
            script="${script}n\n${next}\n\n+${SWAP_SIZE}\n"
            script="${script}t\n${next}\n19\n"
        else
            script="${script}n\np\n${next}\n\n+${SWAP_SIZE}\n"
            script="${script}t\n${next}\n82\n"
        fi
        next=$((next + 1))
    fi
    script="${script}w\n"

    step "Confirmation"
    echo "  Table:    $PARTTABLE"
    echo "  Disk:     $DISK ($(disk_size_str "$DISK"))"
    [ "$EFI" = 1 ] && echo "  Partition 1: EFI System - 512M"
    echo "  Root:     ext4 - ${ROOT_SIZE:-remaining space}"
    [ "$SWAP" = "y" ] && echo "  Swap:     $SWAP_SIZE"
    echo "  Mount:    $MOUNT_POINT"
    echo ""
    confirm_partition_table

    step "Partitioning"
    echo -e "  ${YELLOW}Writing partition table...${NC}"
    run_fdisk "$script"
    echo -e "  ${GREEN}Partition table written${NC}"

    # Set partition variables
    local p=1
    [ "$EFI" = 1 ] && { EFI_PART="${DISK}${p}"; p=$((p + 1)); } || EFI_PART=""
    ROOT_PART="${DISK}${p}"; p=$((p + 1))
    SWAP_PART=""
    [ "$SWAP" = "y" ] && { SWAP_PART="${DISK}${p}"; p=$((p + 1)); }

    # Wait for kernel to detect partitions
    echo -e "  ${YELLOW}Waiting for partitions...${NC}"
    local all_parts="$ROOT_PART $SWAP_PART $EFI_PART"
    for part in $all_parts; do
        [ -z "$part" ] && continue
        # Try with p prefix for NVMe/mmcblk
        wait_for_part "$part" || {
            case "$DISK" in *nvme*|*mmcblk*) part="${DISK}p${part##*[!0-9]}"; wait_for_part "$part" || true ;; esac
        }
    done
    # Re-check with correct naming
    for part in $ROOT_PART $SWAP_PART $EFI_PART; do
        [ -b "$part" ] && continue
        case "$DISK" in *nvme*|*mmcblk*) 
            eval "${part##*/}_PART=\"${DISK}p${part##*[!0-9]}\"" 2>/dev/null || true
        ;; esac
    done
    echo -e "  ${GREEN}Partitions ready${NC}"
}

do_manual() {
    step "Partition sizes (manual)"
    echo "  Enter partition sizes (e.g. +50G, +4096M, or empty for remaining space)"
    echo ""
    read -r -p "  Root partition size: " ROOT_SIZE
    select_yesno "Create swap partition?" && SWAP="y" || SWAP="n"
    [ "$SWAP" = "y" ] && read -r -p "  Swap size: " SWAP_SIZE

    local script="" next=1
    # Partition table type
    [ "$GPT" = 1 ] && script="${script}g\n" || script="${script}o\n"

    # EFI System Partition (GPT only)
    if [ "$EFI" = 1 ]; then
        script="${script}n\n${next}\n\n+512M\n"
        script="${script}t\n${next}\n1\n"
        next=$((next + 1))
    fi

    # Single partition (root only, no swap)
    if [ "$SWAP" != "y" ] && [ -z "$ROOT_SIZE" ]; then
        if [ "$GPT" = 1 ]; then
            script="${script}n\n${next}\n\n\nw\n"
        else
            script="${script}n\np\n${next}\n\n\nw\n"
        fi
        run_fdisk "$script"
        ROOT_PART="${DISK}${next}"
        SWAP_PART=""
        wait_for_part "$ROOT_PART" || {
            case "$DISK" in *nvme*|*mmcblk*) ROOT_PART="${DISK}p${next}" ;; esac
            wait_for_part "$ROOT_PART" || die "Partition $ROOT_PART not detected"
        }
        step "Confirmation"
        echo "  Table: $PARTTABLE"
        echo "  Disk: $DISK ($(disk_size_str "$DISK"))"
        [ "$EFI" = 1 ] && echo "  Partition 1: EFI System - 512M"
        echo "  Root: ext4 - 100% of disk"
        confirm_partition_table
        echo "... already written: single partition"
        return
    fi

    # Root partition
    local root_part_num=$next
    if [ "$GPT" = 1 ]; then
        script="${script}n\n${next}\n\n${ROOT_SIZE:++${ROOT_SIZE}}\n"
    else
        script="${script}n\np\n${next}\n\n${ROOT_SIZE:++${ROOT_SIZE}}\n"
    fi
    next=$((next + 1))

    # Swap partition
    if [ "$SWAP" = "y" ]; then
        if [ "$GPT" = 1 ]; then
            [ -n "$SWAP_SIZE" ] && script="${script}n\n${next}\n\n+${SWAP_SIZE}\n" || script="${script}n\n${next}\n\n\n"
            script="${script}t\n${next}\n19\n"
        else
            [ -n "$SWAP_SIZE" ] && script="${script}n\np\n${next}\n\n+${SWAP_SIZE}\n" || script="${script}n\np\n${next}\n\n\n"
            script="${script}t\n${next}\n82\n"
        fi
        next=$((next + 1))
    fi
    script="${script}w\n"

    step "Confirmation"
    echo "  Table: $PARTTABLE"
    echo "  Disk: $DISK ($(disk_size_str "$DISK"))"
    [ "$EFI" = 1 ] && echo "  Partition 1: EFI System - 512M"
    echo "  Root: ext4 - ${ROOT_SIZE:-remaining space}"
    [ "$SWAP" = "y" ] && echo "  Swap: ${SWAP_SIZE:-remaining space}"
    echo ""
    confirm_partition_table

    step "Partitioning"
    echo -e "  ${YELLOW}Writing partition table...${NC}"
    run_fdisk "$script"
    echo -e "  ${GREEN}Partition table written${NC}"

    # Set partition variables
    ROOT_PART="${DISK}${root_part_num}"
    SWAP_PART=""
    [ "$SWAP" = "y" ] && SWAP_PART="${DISK}${root_part_num}"
    [ "$EFI" = 1 ] && EFI_PART="${DISK}1"

    echo -e "  ${YELLOW}Waiting for partitions...${NC}"
    local all_parts="$ROOT_PART $SWAP_PART $EFI_PART"
    for part in $all_parts; do
        [ -z "$part" ] && continue
        wait_for_part "$part" || {
            case "$DISK" in *nvme*|*mmcblk*) part="${DISK}p${part##*[!0-9]}"; wait_for_part "$part" || true ;; esac
        }
    done
    echo -e "  ${GREEN}Partitions ready${NC}"
}

do_format() {
    local fstype="${1:-ext4}"

    step "Format"
    echo -e "  ${YELLOW}Formatting $ROOT_PART (${fstype})...${NC}"
    case "$fstype" in
        ext4) mkfs.ext4 -F "$ROOT_PART" >/dev/null 2>&1 || die "mkfs.ext4 failed" ;;
        ext3) mkfs.ext4 -F -t ext3 "$ROOT_PART" >/dev/null 2>&1 || die "mkfs.ext3 failed" ;;
        btrfs) mkfs.btrfs -f "$ROOT_PART" >/dev/null 2>&1 || die "mkfs.btrfs failed" ;;
        xfs) mkfs.xfs -f "$ROOT_PART" >/dev/null 2>&1 || die "mkfs.xfs failed" ;;
        *) die "Unsupported filesystem: $fstype" ;;
    esac
    echo -e "  ${GREEN}$ROOT_PART formatted as ${fstype}${NC}"

    if [ -n "$SWAP_PART" ]; then
        echo -e "  ${YELLOW}Formatting $SWAP_PART (swap)...${NC}"
        mkswap "$SWAP_PART" >/dev/null 2>&1 || echo -e "  ${YELLOW}mkswap warning${NC}"
        echo -e "  ${GREEN}$SWAP_PART formatted as swap${NC}"
    fi
}

do_mount() {
    step "Mount"
    mkdir -p "$MOUNT_POINT" 2>/dev/null
    mount "$ROOT_PART" "$MOUNT_POINT" || die "Mount $ROOT_PART to $MOUNT_POINT failed"
    echo -e "  ${GREEN}$ROOT_PART mounted at $MOUNT_POINT${NC}"

    if [ -n "$SWAP_PART" ]; then
        swapon "$SWAP_PART" 2>/dev/null && echo -e "  ${GREEN}Swap $SWAP_PART activated${NC}"
    fi
}

show_result() {
    step "Result"
    echo "  DISK=$DISK"
    echo "  ROOT_PART=$ROOT_PART"
    echo "  SWAP_PART=${SWAP_PART:-<none>}"
    echo "  MOUNT_POINT=$MOUNT_POINT"
    echo ""
    echo -e "  ${GREEN}Ready for nhopkg installation!${NC}"
    echo "  Source these variables: . /dev/stdin <<< \"DISK=$DISK ROOT_PART=$ROOT_PART ...\""
    echo "  Or write to /tmp/install.conf:"
    echo "    echo \"DISK=$DISK\" > /tmp/install.conf"
    echo "    echo \"ROOT_PART=$ROOT_PART\" >> /tmp/install.conf"
    echo "    echo \"SWAP_PART=$SWAP_PART\" >> /tmp/install.conf"
    echo "    echo \"MOUNT_POINT=$MOUNT_POINT\" >> /tmp/install.conf"
}

do_reboot_prompt() {
    echo ""
    if select_yesno "Reboot now?"; then
        reboot -f
    fi
}

main() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     NeonatoX Disk Partitioning Wizard    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}WARNING: This tool will DESTROY ALL DATA on the selected disk.${NC}"
    echo -e "${RED}Back up important data before proceeding.${NC}"
    echo ""

    step "Select disk"
    select_disk

    step "Partition table"
    select_table_type

    echo ""
    echo "Partitioning schemes:"
    echo "  1) Auto — single ext4 root + optional swap"
    echo "  2) Manual — specify partition sizes"
    echo ""
    local scheme
    while :; do
        read -r -p "Choose scheme (1-2): " scheme || die
        case "$scheme" in
            1) do_auto; break ;;
            2) do_manual; break ;;
            *) echo -e "${YELLOW}Enter 1 or 2${NC}" ;;
        esac
    done

    # Filesystem selection (only show available)
    local fstype="ext4" i=2
    local fs_menu="" fs_opts="ext4"
    echo ""
    echo "Filesystem types:"
    echo "  1) ext4  (default)"
    command -v mkfs.btrfs >/dev/null 2>&1 && {
        echo "  $i) btrfs"
        fs_menu="${fs_menu} $i) btrfs"
        fs_opts="${fs_opts} btrfs"
        i=$((i + 1))
    }
    command -v mkfs.xfs >/dev/null 2>&1 && {
        echo "  $i) xfs"
        fs_opts="${fs_opts} xfs"
        i=$((i + 1))
    }
    echo "  $i) ext3"
    fs_opts="${fs_opts} ext3"
    local max=$i
    local fs_choice
    read -r -p "Select filesystem (1-${max}) [1]: " fs_choice
    case "$fs_choice" in
        2) command -v mkfs.btrfs >/dev/null 2>&1 && fstype="btrfs" || fstype="ext3" ;;
        3) command -v mkfs.xfs >/dev/null 2>&1 && fstype="xfs" || fstype="ext3" ;;
        4) fstype="ext3" ;;
    esac

    do_format "$fstype"
    do_mount
    show_result
    do_reboot_prompt
}

main "$@"
