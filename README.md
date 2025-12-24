[![License: GPLv3+](https://img.shields.io/badge/license-GPLv3%2B-blue.svg)](LICENSE)[![Language: Bash](https://img.shields.io/badge/language-Bash-green.svg)](https://www.gnu.org/software/bash/)[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/cargabsj175/neonatox-live-boot)

Neonatox Live Boot
==================

**Neonatox Live Boot** is a from-scratch Linux Live ISO builder. It is designed as an educational and experimental project that demonstrates, step by step, how a complete live Linux system boots, detects hardware, mounts a real root filesystem, and hands control to systemd.

This project intentionally avoids high-level frameworks (such as dracut or live-build) in order to expose the real boot mechanics.

* * *

Project Goals
-------------

*   Teach how Linux boots in real conditions
*   Build a functional Live ISO without hidden abstractions
*   Remain understandable to people learning low-level Linux
*   Serve as a base for experimentation or custom distributions

* * *

Key Features
------------

*   BIOS and UEFI boot support using GRUB
*   Full system snapshot packed as SquashFS (`rootfs.squashfs`)
*   Writable live system using OverlayFS (RAM-based)
*   Minimal initramfs built with BusyBox
*   Explicit hardware detection (USB, SATA, NVMe, CD/DVD, IDE)
*   Keyboard support in early boot (USB HID and PS/2)
*   Clean handoff to systemd as PID 1

* * *

Repository Structure
--------------------
```
neonatox-live-boot/
├── build.sh              → Main ISO build script
├── initramfs/
│   ├── busybox           → Static BusyBox binary
│   └── init              → Initramfs init script
├── iso/
│   └── background.png    → GRUB background image
├── docs/
│   ├── boot-flow.svg     → Visual boot diagram
│   ├── initramfs-design.html
│   ├── device-detection.html
│   ├── overlayfs.html
│   ├── systemd-handoff.html
│   └── debugging.html
└── README.html
```

The `output/` directory is intentionally ignored, as it only contains generated ISO images.

* * *

How It Works (High-Level)
-------------------------

1.  GRUB loads the kernel and initramfs
2.  The kernel executes `/init` inside initramfs
3.  Minimal virtual filesystems are mounted
4.  Essential kernel modules are loaded
5.  Boot media is detected by probing real block devices
6.  `rootfs.squashfs` is located and mounted read-only
7.  An OverlayFS root is created using tmpfs
8.  A clean environment is prepared for systemd
9.  `switch_root` hands control to systemd

A complete visual diagram is available in `docs/boot-flow.svg`.

* * *

Why This Project Exists
-----------------------

Most live systems hide complexity behind layers of tooling. Neonatox Live Boot intentionally does the opposite.

During development, many common assumptions were proven false:

*   Devices do not always exist in `/dev` early
*   udev is not available in initramfs
*   systemd requires a very specific environment
*   Errors often appear much later than their real cause

These lessons are documented in detail in the `docs/` directory.

* * *

Usage
-----

1.  Clone the repository
2.  Place a static BusyBox binary in `initramfs/busybox`
3.  Customize `iso/background.png` if desired
4.  Run the build script as root:

sudo ./build.sh

The resulting ISO will be generated in:

output/neonatox-2026-x86\_64.iso

* * *

Dependencies
------------

*   grub (BIOS and EFI tools)
*   xorriso
*   squashfs-tools
*   busybox (static binary)
*   zstd (for kernel module decompression)

* * *

Philosophy
----------

Neonatox Live Boot is:

*   Educational
*   Experimental
*   Minimal but correct

It is not intended to replace existing live frameworks. It is intended to help you understand them.

* * *

License
-------

This project is released under the GPLv3 (or later). You are free to use, modify, and redistribute it.

If you learn something from this project, it has already succeeded.
