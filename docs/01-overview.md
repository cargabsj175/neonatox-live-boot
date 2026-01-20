# Overview & Philosophy

## What Neonatox Live Boot Is

Neonatox Live Boot is a handcrafted live boot system that builds a complete Linux live environment using: 

  * A custom initramfs
  * A squashfs root filesystem
  * OverlayFS for a writable runtime layer
  * systemd as PID 1



Unlike automated systems, every stage of the boot process is explicit and under developer control. 

## What This Project Is Not

Neonatox Live Boot intentionally avoids: 

  * dracut
  * live-build
  * initramfs generators with opaque logic



This is not because those tools are bad, but because they hide the learning process. 

## Educational First, Practical Second

The primary goal is education. However, the final system is robust enough to boot from: 

  * USB
  * CD/DVD
  * Virtual machines
  * IDE, SATA, NVMe, and USB storage



The design choices are explained throughout this documentation, including mistakes made during development and how they were resolved. 
