# Ventoy Support Design

This document explains how Neonatox Live Boot achieves full compatibility with Ventoy **without modifying, patching, or depending on Ventoy internals**. The solution is implemented entirely inside the custom `initramfs` and `build.sh`. 

## Why Ventoy Is Special

Ventoy does not boot a Linux ISO in the traditional way. Instead of extracting files, Ventoy: 

  * Boots the kernel and initramfs from the ISO
  * Leaves the ISO file intact on a data partition
  * Allows multiple ISO files to coexist on the same USB
  * Injects helper directories such as `/ventoy` or `/vtoy`



Because of this, assumptions commonly made by live systems often fail: 

  * The boot filesystem is not necessarily ISO9660
  * The root filesystem is not mounted automatically
  * The correct ISO cannot be reliably identified by name or label



## Design Goals

  * No Ventoy patches or hooks
  * No reliance on ISO filenames
  * No reliance on filesystem labels
  * Works with multiple ISOs on the same USB
  * Safe and deterministic ISO selection



## Filesystem Support

Ventoy USB partitions commonly use filesystems such as: 

  * FAT / VFAT
  * exFAT
  * NTFS



To ensure access to Ventoy partitions, the initramfs explicitly loads: 
    
    
    iso9660
    vfat
    fat
    exfat
    ntfs3
    

This guarantees that the partition containing ISO files can be mounted regardless of the filesystem chosen by the user. 

## ISO Matching by Cryptographic Hash

The key design decision that makes Ventoy support reliable is **cryptographic matching of the root filesystem**. 

### build.sh Responsibility

During build time, `build.sh` computes the SHA256 checksum of `rootfs.squashfs` and embeds it into the initramfs as: 
    
    
    /rootfs.sha256
    

This permanently binds the initramfs to the exact root filesystem it expects. 

### init Responsibility

At boot time, the initramfs: 

  * Mounts candidate partitions
  * Scans for ISO files in the root of the filesystem
  * Loop-mounts each ISO
  * Checks for `rootfs.squashfs` inside the ISO
  * Computes its SHA256 hash
  * Compares it with `/rootfs.sha256`



Only when the hashes match is the ISO accepted as the correct boot source. 

## Ventoy Environment Detection

The initramfs detects a Ventoy environment using a minimal and stable condition: 
    
    
    /ventoy  or  /vtoy
    

These directories are injected by Ventoy and are present both in legacy and UEFI Ventoy boot modes. 

## USB Controller Detection: The Hidden Challenge

A critical discovery during development revealed that Ventoy compatibility depends heavily on proper USB controller detection in the initramfs. Early testing showed that while Neonatox ISOs worked in Ventoy, other distributions like Alpine Linux failed when using the same initramfs.

### Root Cause: Missing PCI Interface Modules

The issue was traced to missing USB PCI interface modules in the initramfs module loading sequence. While standard host controller modules (`xhci_hcd`, `ehci_hcd`, etc.) were loaded, the essential PCI bridge modules were missing:

  * `xhci_pci` \- USB 3.x (xHCI) PCI interface
  * `ehci_pci` \- USB 2.0 (eHCI) PCI interface
  * `ohci_pci` \- USB 1.1 (OHCI) PCI interface



Without these modules, the kernel cannot detect physical USB devices connected through PCI Express interfaces, which is common in most modern hardware.

### Solution: Complete USB Module Loading

The initramfs now loads a comprehensive set of USB modules to ensure detection across all hardware types:
    
    
    MEDIA="loop scsi_mod sd_mod sr_mod cdrom \
           usbcore usb_common usb-storage uas \
           xhci_hcd ehci_hcd uhci_hcd \
           xhci_pci ehci_pci ohci_pci \
           ahci libata zram"
    

This guarantees USB device enumeration regardless of the underlying hardware architecture.

## Kernel Version Differences in Device Management

Testing across different kernel versions revealed another critical compatibility issue related to how device nodes are created.

### Behavioral Change in Linux Kernel 6.15+

A significant behavioral change was introduced in Linux kernel version 6.15:

  * **Kernel ≥ 6.15** : Automatically creates partition device nodes (like `/dev/sdb1`) when the partition table is read, even without udev.
  * **Kernel ≤ 6.14** : Only creates the disk device node (like `/dev/sdb`). Partition nodes must be created manually or by udev/mdev.



This explains why the same initramfs worked with newer kernels but failed with older ones like Alpine's 6.12 kernel.

### Solution: Proactive Partition Node Creation

To ensure compatibility across all kernel versions, the initramfs now includes a function that proactively creates missing partition device nodes by reading partition information directly from `/sys/block/`:
    
    
    create_partitions() {
        local disk_base="$1"      # e.g., sda
        local disk_dev="$2"       # e.g., /dev/sda
        local part_prefix="$3"    # "" for sd/hd, "p" for mmcblk
    
        i=1
        while [ $i -le 16 ]; do
            part_name="${disk_base}/${i}"
            part_dev="${disk_dev}${part_prefix}${i}"
    
            if [ -e "/sys/block/$part_name" ]; then
                if [ ! -b "$part_dev" ]; then
                    if [ -f "/sys/block/$part_name/dev" ]; then
                        read MAJ MIN < "/sys/block/$part_name/dev"
                        mknod "$part_dev" b "$MAJ" "$MIN" 2>/dev/null
                    fi
                fi
            else
                break
            fi
            i=$((i + 1))
        done
    }
    

This function ensures that partition nodes exist even on older kernels that don't create them automatically.

## Critical Detail: BusyBox losetup Limitation

The final issue preventing Ventoy boot was **not Ventoy itself** , but a limitation of the BusyBox implementation used inside the initramfs. 

### The Problem

Many full Linux systems rely on: 
    
    
    losetup --show -f file.iso
    

However, the BusyBox `losetup` applet does **not** support the `--show` option. 

As a result: 

  * The command silently failed
  * The loop device variable remained empty
  * The ISO was never actually mounted
  * `rootfs.squashfs` was never found



This created a false impression that Ventoy was incompatible. 

### The Solution

The fix was to explicitly query the loop device after attachment: 
    
    
    LOOP="$(losetup -f "$ISO" && losetup -a | grep "$ISO" | sed 's/:.*//')"
    

This approach: 

  * Works with BusyBox
  * Does not require GNU util-linux
  * Correctly retrieves the loop device
  * Restores reliable ISO mounting



Once this change was applied, Ventoy boot worked correctly and consistently. 

## Why This Matters

This highlights important lessons when designing initramfs-based systems: 

  * Tool behavior inside initramfs is not the same as a full system
  * BusyBox applets have reduced feature sets
  * Silent failures can lead to misleading conclusions
  * Hardware detection requires complete module loading (including PCI interfaces)
  * Kernel version differences can break assumptions about device node creation



Ventoy itself was functioning exactly as designed. The challenges were in our initramfs implementation and understanding of low-level hardware interaction.

## Summary

  * Ventoy support is fully initramfs-driven
  * No Ventoy patches or plugins are required
  * ISO selection is cryptographically verified
  * USB detection requires both host controller and PCI interface modules
  * Older kernels need manual partition node creation
  * BusyBox limitations must be worked around explicitly
  * The solution is portable, robust, and maintainable across kernel versions



This design preserves Neonatox's educational philosophy while achieving real-world compatibility with modern multiboot tools across different hardware platforms and kernel versions. 
