# Boot Flow

This section describes the complete boot sequence from firmware to systemd. 

## High-Level Flow
    
    
    Firmware (BIOS/UEFI)
            ↓
    GRUB
            ↓
    Linux Kernel
            ↓
    Initramfs (/init)
            ↓
    rootfs.squashfs
            ↓
    OverlayFS
            ↓
    switch_root
            ↓
    systemd (PID 1)
    

## Why GRUB

GRUB is used instead of syslinux primarily for flexibility and modern firmware support. While linux-live traditionally uses syslinux, GRUB is widely available and easier to integrate with EFI systems. 

## Kernel Responsibilities

The kernel initializes hardware, mounts the initramfs as a temporary root, and executes the `/init` script. 

## Initramfs Responsibilities

  * Load minimal drivers
  * Detect the boot medium
  * Mount the squashfs root filesystem
  * Create an overlay filesystem
  * Prepare a clean environment for systemd


