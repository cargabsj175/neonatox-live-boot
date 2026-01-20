# Live Configuration Stage (`live-config.sh`)

## Purpose

`live-config.sh` implements an **optional early configuration stage** for Neonatox Live Boot. Its purpose is to configure language, keyboard, timezone, and the live user **before the real root filesystem is activated**. 

This stage is **executed inside the initramfs** and is enabled **only when explicitly requested** by the user through the bootloader. 

* * *

## Design Philosophy

The design of `live-config.sh` follows the core principles of Neonatox Live Boot: 

  * Explicit behavior
  * No implicit automation
  * Deterministic execution
  * Safe failure modes
  * Educational clarity



By default, the live system boots non-interactively. User interaction is introduced **only when explicitly selected**. 

* * *

## Activation via GRUB

The configuration stage is enabled by selecting the dedicated GRUB menu entry: 
    
    
    menuentry "Neonatox Live (Lang & live user config)" {
        linux /boot/vmlinuz quiet neoconfig=1
        initrd /boot/initramfs.img
    }
    

The presence of the kernel parameter `neoconfig=1` activates `live-config.sh`. If the parameter is absent, the configuration stage is skipped entirely. 

* * *

## Position in the Boot Flow

When `neoconfig=1` is present, the boot flow becomes: 
    
    
    initramfs
      ↓
    live-config.sh
      ↓
    switch_root
      ↓
    systemd (PID 1)
      ↓
    ready-to-use live system
    

Without `neoconfig=1`, the system proceeds directly from the initramfs to `switch_root`. 

* * *

## Interactive Language Selection

If `/dev/tty1` is available, the script presents an optional interactive menu allowing the user to select: 

  * System language
  * Timezone
  * Keyboard layout



Characteristics: 

  * Timeout-safe (60 seconds)
  * Default selection if no input is provided
  * No dependency on dialog or ncurses
  * Direct output to `/dev/tty1`



If no interactive console is available, the script continues automatically using default values. 

* * *

## Locale Configuration

The selected locale is written explicitly to: 
    
    
    /etc/locale.conf
    

Example: 
    
    
    LANG=es_VE.UTF-8
    

No helper tools such as `localectl` are used. This ensures predictable behavior regardless of the underlying distribution. 

* * *

## Timezone Configuration

If the selected timezone exists in the target system, the script: 

  * Creates `/etc/localtime` as a symbolic link
  * Writes `/etc/timezone` when applicable



This guarantees compatibility with both Arch-like and Debian-like layouts. 

* * *

## Keyboard Configuration

### Console Keyboard

If console keymaps are available, the following file is generated: 
    
    
    /etc/vconsole.conf
    

### X11 Keyboard

If X11 configuration directories exist, a static keyboard configuration file is created: 
    
    
    /etc/X11/xorg.conf.d/00-keyboard.conf
    

This avoids reliance on runtime auto-detection and ensures consistency. 

* * *

## Live User Creation

The live environment uses a single predefined user: 

  * Username: `neonatox`
  * UID/GID: `999`
  * Home directory: `/home/neonatox`



A fixed identity avoids permission issues with OverlayFS and simplifies the boot logic. 

* * *

## Password Handling

The user password is defined in the script and hashed using BusyBox `cryptpw`. 

This process does not rely on PAM, interactive tools, or external helpers, making it safe to run inside the initramfs. 

* * *

## Group Membership

The live user is appended to common system groups if they exist: 

  * adm
  * video
  * wheel
  * seat
  * input



Membership is added safely without duplication. 

* * *

## Passwordless Sudo

To provide a fully usable live environment, passwordless sudo is enabled via: 
    
    
    /etc/sudoers.d/99-live
    

This configuration applies only to the live session. 

* * *

## TTY Autologin (systemd only)

Automatic login on TTY1 is currently implemented **only for systemd-based systems**. 

This is achieved by installing a systemd service override: 
    
    
    /etc/systemd/system/getty@tty1.service.d/override.conf
    

This approach is used because it is the cleanest and least intrusive method available when systemd is present. 

On systems using alternative init systems such as OpenRC or SysVinit, no autologin mechanism is currently applied. The live system will still function correctly, but login will be manual. 

Future adaptations may introduce equivalent mechanisms for other init systems, but these are intentionally not implemented at this stage. 

* * *

## User Startup Files

### .xinitrc

Automatically starts the XFCE desktop: 
    
    
    exec startxfce4
    

### .bash_profile

Automatically launches `startx` when logging in from the console. 

This allows a complete graphical session without a display manager. 

* * *

## Desktop Environment Requirement

The live configuration stage assumes the presence of the **XFCE desktop environment**. 

Specifically, the following command must be available: 
    
    
    startxfce4
    

On distributions other than Neonatox, the live environment will operate correctly only if `xfce4` (or an equivalent package providing `startxfce4`) is installed. 

If `startxfce4` is not present, the system will still boot normally, but no graphical session will be started automatically. 

* * *

## Portability and Init System Independence

Although Neonatox Live Boot uses `systemd` by default, the core logic of `live-config.sh` is largely **init-system independent**. 

All configuration steps are implemented using: 

  * Direct file manipulation
  * POSIX-compatible shell logic
  * BusyBox-compatible utilities



The only systemd-specific component currently implemented is TTY autologin. This limitation is explicit and intentional. 

The design allows future adaptation to OpenRC or SysVinit by replacing init-specific handling without altering the core configuration logic. 

* * *

## What This Script Does Not Do

  * Does not detect or mount devices
  * Does not manage filesystems
  * Does not start services
  * Does not require systemd to execute



Its scope is intentionally limited to early live-system configuration. 

* * *

## Summary

`live-config.sh` is an **optional pre-root configuration stage** controlled explicitly by the bootloader. 

The initramfs makes the system boot.  
**live-config.sh makes the system personal — without contaminating the root filesystem.**
