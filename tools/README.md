
Neonatox Live Boot Tools Builder
================================

This toolset is part of the Neonatox initramfs build workflow. Its purpose is to compile essential binaries in a fully **static** way using `musl`, ensuring portability, host independence, and compatibility with minimal environments.

General Architecture
--------------------

The system is built around a **central builder** that discovers and executes individual tool scripts. Each tool is fully self-contained and responsible for:

*   Fetching its source code
*   Configuring a minimal build
*   Forcing static linking
*   Validating the resulting binary
*   Installing it into the initramfs

The main dispatcher controls selective or full build execution.

Reference: `build-tools.sh` :contentReference\[oaicite:0\]{index=0}

Included Tools
--------------

### Bash

A statically linked and optimized version of the shell is compiled with only essential features. The resulting binary is validated to ensure it has no dynamic dependencies before integration.

Reference: `bash.sh` 

### BusyBox

Built as a single static binary providing multiple core utilities. A predefined configuration is used and static linking is enforced during compilation.

Reference: `busybox.sh` 

### e2fsprogs

A minimal subset focused on essential ext filesystem tools is compiled. Unnecessary components are disabled to reduce size and complexity.

Reference: `e2fsprogs.sh`

Key Features
------------

*   Fully static compilation
*   Host system independence
*   Modular and extensible design
*   Automatic binary validation
*   Direct output into initramfs

Execution Flow
--------------


```

./build-tools.sh --all
./build-tools.sh --busybox
./build-tools.sh --bash --busybox
./build-tools.sh --clean


```

Design Notes
------------

The design prioritizes:

*   Minimalism
*   Full control over the runtime environment
*   System reproducibility

Each tool is built in isolation, keeping the pipeline clear and easy to debug.
