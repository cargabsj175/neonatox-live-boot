# Initramfs Design

## Purpose of the Initramfs

The initramfs is not a mini-root filesystem intended to stay alive. Its only job is to: 

  * Detect boot media
  * Mount the real root filesystem
  * Hand control to the real init system



Everything else is intentionally minimal. 

## Why BusyBox

BusyBox is used because: 

  * It provides a predictable shell environment
  * It avoids dependency chains
  * It keeps the initramfs small and deterministic



Importantly, BusyBox does **not** provide a full device manager. This is a design choice, not a limitation. 

## /dev Handling Strategy

One of the most critical lessons learned during development was that device management must be staged. 

### What Was Tried (and Failed)

  * Mounting devtmpfs too early
  * Relying on hotplug helpers
  * Expecting /dev to populate automatically



These approaches resulted in: 

  * Missing block devices
  * Broken dbus later in systemd
  * Non-interactive consoles



### The Working Model

Neonatox Live Boot uses: 

  * Static device nodes created at build time
  * devtmpfs only when preparing the final root
  * mdev only for minimal rescans



This ensures that: 

  * /dev is usable before systemd starts
  * systemd can take full control later



## Why /proc/sys/kernel/hotplug Is Not Used

Modern kernels no longer rely on `/proc/sys/kernel/hotplug`. Attempting to use it results in: 
    
    
    sh: /proc/sys/kernel/hotplug: No such file or directory
    

This project intentionally avoids legacy hotplug mechanisms. 
