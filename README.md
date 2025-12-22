[![License: GPLv3+](https://img.shields.io/badge/license-GPLv3%2B-blue.svg)](LICENSE)[![Language: Bash](https://img.shields.io/badge/language-Bash-green.svg)](https://www.gnu.org/software/bash/)[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/cargabsj175/neonatox-live-boot)


Neonatox Live Boot+
====================

**Neonatox Live Boot** is a from-scratch **Linux Live ISO builder** designed to create lightweight, customizable bootable images based on a snapshot of your current system. Ideal for custom distributions, rescue tools, installers, or ephemeral environments.

✨ Features
----------

*   **Dual BIOS / UEFI boot support** via GRUB
*   **SquashFS root filesystem** (`rootfs.squashfs`) with XZ compression
*   **Runtime environment using `overlayfs`** (writeable layer in RAM)
*   **Minimal initramfs** built with BusyBox and essential kernel modules
*   **Automatic hardware detection**: USB, NVMe, SATA, CD/DVD, PS/2 and USB HID keyboards
*   **Graphical GRUB menu** with custom background, font, and multi-resolution support
*   **No external dependencies** beyond standard tools (`grub`, `xorriso`, `mksquashfs`, etc.)

🚀 Usage
--------

1.  Clone this repository:
    
        git clone https://github.com/your-username/neonatox-live.git
        cd neonatox-live
    
2.  Install required dependencies:
    
        # On Debian/Ubuntu-based systems:
        sudo apt install grub-efi-amd64-bin grub-pc-bin xorriso squashfs-tools zstd busybox
    
3.  Place a static `busybox` binary in `initramfs/busybox` (or build one yourself).
4.  Optional: customize `iso/background.png` to change the GRUB background.
5.  Run the build script:
    
        sudo ./build.sh
    
    ⚠️ **Root privileges are required** to read the full filesystem when creating `rootfs.squashfs`.
    
6.  The generated ISO will be located at `output/neonatox-2026-x86_64.iso`.

🧠 Technical Notes
------------------

*   The script captures your entire root filesystem (`/`) into the SquashFS image, excluding temporary and cache directories (see `EXCLUDES`).
*   The initramfs includes **essential kernel modules** for booting from USB, NVMe, SATA, and optical media.
*   The custom init (`initramfs/init`) locates and mounts the partition containing `rootfs.squashfs`, then performs `switch_root` into the overlay-based runtime system.

🛠️ Customization
-----------------

*   Modify `REQ_DIRS` and `NEEDED_MODULES` to include additional drivers or subsystems.
*   Edit `grub.cfg` to add boot entries (e.g., debug mode, memory tests, etc.).
*   Extend the initramfs `init` script to support persistence, networking, or custom hardware initialization.

📜 License
----------

This project is free software. You may use, modify, and redistribute it under the terms of the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html) (or any license you choose—just remember to define it!).
