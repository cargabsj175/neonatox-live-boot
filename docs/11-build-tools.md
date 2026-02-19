# Neonatox Live Boot Tools Builder (`build-tools.sh`)

The Neonatox Live Boot Tools Builder is part of the initramfs build workflow. Its purpose is to compile essential system binaries in a fully **static** manner using `musl`.

This ensures:

*   Portability
*   Host system independence
*   Compatibility with minimal environments
*   Predictable runtime behavior

* * *

## General Architecture

The system is structured around a **central dispatcher** (`build-tools.sh`) that discovers and executes individual tool-specific build scripts.

Each tool script is fully self-contained and responsible for:

*   Fetching its source code
*   Configuring a minimal build
*   Enforcing static linking
*   Validating the resulting binary
*   Installing it into the initramfs staging area

This modular design allows selective or full builds while maintaining a clean and debuggable pipeline.

* * *

## Included Tools

### Bash

A statically linked and optimized version of the GNU Bash shell is compiled with only essential features enabled.

The resulting binary is validated to confirm that it contains **no dynamic dependencies** before being integrated into the initramfs.

Reference: `bash.sh`

* * *

### BusyBox

BusyBox is compiled as a single static binary providing multiple core utilities required by the initramfs.

A predefined configuration is used to ensure deterministic behavior, and static linking is enforced during compilation.

Reference: `busybox.sh`

* * *

### e2fsprogs

A minimal subset of e2fsprogs is compiled, focusing only on essential ext filesystem utilities.

Unnecessary components are disabled to reduce binary size and complexity.

Reference: `e2fsprogs.sh`

* * *

## Key Features

*   Fully static compilation
*   Complete host system independence
*   Modular and extensible structure
*   Automatic binary validation
*   Direct integration into initramfs

* * *

## Execution Flow

The central builder supports selective execution:

./build-tools.sh --all
./build-tools.sh --busybox
./build-tools.sh --bash --busybox
./build-tools.sh --clean

This allows granular control over which tools are compiled and installed.

* * *

## Design Notes

The toolchain prioritizes:

*   Minimalism
*   Full runtime control
*   System reproducibility
*   Isolation of build components

Each tool is built independently, keeping the build process transparent and easy to debug.

* * *

## Philosophical Alignment

The Tools Builder reinforces the educational philosophy of Neonatox Live Boot:

*   No opaque dependency chains
*   No reliance on host system libraries
*   No unpredictable runtime behavior

Everything included in the initramfs is compiled deliberately, validated explicitly, and understood completely.
