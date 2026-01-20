# OverlayFS and Root Filesystem

## Why OverlayFS

A live system must appear writable while keeping its base immutable. OverlayFS provides this cleanly and efficiently. 

## Critical Discovery

An important discovery during development was: 

> Mounting tmpfs before creating overlay directories causes them to disappear. 

The correct order is: 

  1. Mount tmpfs
  2. Create upper and work directories
  3. Mount overlay



## Overlay Layout
    
    
    lowerdir = squashfs (read-only)
    upperdir = tmpfs (writable)
    workdir  = tmpfs (overlay metadata)
    

This layout allows a fully writable runtime system while keeping the original squashfs untouched. 
