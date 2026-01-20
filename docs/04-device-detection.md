# Device Detection

## The Core Problem

The most difficult part of a live system is not mounting squashfs. It is reliably finding it. 

Many systems assume: 

  * /dev/sr0 exists
  * /dev/sda1 exists
  * udev is running



None of these assumptions are valid in early initramfs. 

## What the Kernel Actually Provides

In early boot, the kernel exposes devices primarily via: 

  * /sys/class
  * /sys/block



If a device exists in sysfs but not in /dev, the problem is userspace, not the kernel. 

## Why mdev Is Used Carefully

mdev is used only to populate minimal device nodes after: 

  * Modules are loaded
  * SCSI buses are rescanned



Blind reliance on mdev was found to be insufficient. 

## Multi-Pass Detection Strategy

Neonatox Live Boot performs: 

  * Multiple detection passes
  * Short delays between passes
  * Ordered probing of devices



The probing order is intentional: 

  1. Optical media
  2. NVMe devices
  3. SATA / USB disks
  4. Legacy IDE



## Why This Matters

This approach: 

  * Works on real hardware
  * Works on VirtualBox and QEMU
  * Does not require udev


