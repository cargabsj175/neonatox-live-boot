# Boot Modes - Neonatox Live Boot

Official boot options and kernel flags for the Neonatox Live system

## Overview

Neonatox Live Boot uses a fully custom **initramfs** designed for robust hardware detection, optional RAM-based overlays, Ventoy compatibility, and controlled debugging. 

All boot flags are parsed and acted upon **before switch_root**. 

* * *

## Available Boot Modes

### 1\. Live (Default)
    
    
    linux /boot/vmlinuz quiet loglevel=3
    

  * Fast boot
  * tmpfs overlay (RAM)
  * No interactive configuration
  * No integrity re-check



* * *

### 2\. Live (Language & Live User Config)
    
    
    linux /boot/vmlinuz quiet neoconfig=1
    

  * Language selection
  * Keyboard layout
  * Timezone
  * Live user setup



* * *

### 3\. Live (Failsafe graphics)
    
    
    linux /boot/vmlinuz quiet nomodeset vga=normal
    

  * Disables KMS
  * Recommended for legacy GPUs and virtual machines



* * *

### 4\. Live (Kernel DEBUG)
    
    
    linux /boot/vmlinuz debug=1 loglevel=7
    

  * Maximum kernel verbosity
  * Driver and hardware diagnostics
  * Does not affect initramfs logic



* * *

### 5\. Live (Initramfs Debug Levels)

Neonatox provides **three deterministic initramfs debug breakpoints**. Each level stops the boot process at a precise stage. 
    
    
    linux /boot/vmlinuz initrd_debug=1|2|3
    

#### initrd_debug=1 – Early initramfs

  * Console and virtual filesystems mounted
  * Kernel modules loaded
  * Before ZRAM and device scan



#### initrd_debug=2 – Storage & integrity stage

  * ZRAM overlay configured (if enabled)
  * Ventoy environment detected
  * Devices scanned
  * rootfs.squashfs located and verified
  * squashfs mounted



#### initrd_debug=3 – Pre-switch_root

  * Overlay filesystem mounted
  * newroot prepared
  * Live configuration executed (if enabled)
  * System ready to switch_root



**Note:** All debug levels drop into an emergency shell. Boot will not continue automatically. 

* * *

## Optional Performance & Safety Flags

### ZRAM Overlay
    
    
    linux /boot/vmlinuz zram=1
    

  * Uses compressed RAM as overlay upper layer
  * Automatic sizing based on total memory
  * lz4 compression when available
  * Falls back to tmpfs if unavailable



* * *

### RootFS Integrity Verification
    
    
    linux /boot/vmlinuz checkhash=1
    

  * Full SHA256 verification of rootfs.squashfs
  * Applies to both physical media and Ventoy ISOs
  * Slower but ensures full integrity



* * *

## Supported Kernel Flags

  * neoconfig=1 – Interactive live setup
  * zram=1 – Enable ZRAM overlay
  * checkhash=1 – Full rootfs hash verification
  * initrd_debug=1 – Early initramfs shell
  * initrd_debug=2 – Storage & integrity shell
  * initrd_debug=3 – Pre-switch_root shell
  * debug=1 – Kernel debug
  * loglevel=7 – Maximum kernel verbosity
  * nomodeset – Disable KMS



* * *

## Boot Flow Summary
    
    
    Firmware (BIOS/UEFI)
            ↓
    GRUB
            ↓
    Linux Kernel
            ↓
    initramfs
            ↓
    (optional) ZRAM overlay (zram=1)
            ↓
    (optional) Ventoy ISO detection
            ↓
    (optional) rootfs verification (checkhash=1)
            ↓
    (optional) live-config (neoconfig=1)
            ↓
    switch_root
            ↓
    init system (systemd or /sbin/init)
    
