## Status

**STATUS**: `RELEASE/STABLE`

Descriptions:
- `DEV/IDEA`       : Conceptual phase; only covers specific pieces of the main feature.
- `DEV/RAW`        : Core feature implemented, but lacks validation for positive/success cases.
- `DEV/WIP`        : Core feature implemented with basic safety checks and negative case handling.
- `ERR/FATAL`      : Currently disabled or unusable due to critical errors.
- `ERR/MINOR`      : Main feature is usable, but fails under specific conditions or edge cases.
- `RELEASE/STABLE` : Fully implemented, tested, and ready for use.

## About

This Zsh script is a watch-mode synchronization utility designed to streamline embedded firmware development. It continuously monitors and pulls compiled binaries (`.srec`) and map files (`.map`) from a remote Coder workspace to a local environment.

Key features include:
- **Smart Synchronization:** Utilizes `rsync` with checksum validation to transfer files only when their contents differ, minimizing unnecessary network traffic.
- **Parallel Processing:** Dispatches up to 8 concurrent SSH/rsync connections to handle multiple build targets efficiently.
- **RTT Address Auto-Extraction:** Automatically parses updated `.map` files using regex to locate and display the `_SEGGER_RTT` memory block address, which is essential for configuring Segger Real-Time Terminal debugging.
- **Secure Tunneling:** Integrates directly with the `coder` CLI via a customized SSH `ProxyCommand` for secure access to the remote workspace.

## Disclaimer

> This program/script was created for my own work and is shared here in case others find it useful for a similar need. I am *NOT* responsible for any issues, damage, or risks that may result from running this program/script or any other content from this repository. By *downloading* and *executing* this program/script, you acknowledge that you understand and accept the associated risks.
>
> Please be careful with any program/script that requires `sudo`/`administrator` privileges, especially when downloading and running scripts from external websites.
>
> This program/script is published as open-source under the GNU General Public License (GPL). Feel free to use it for any purpose. 
> 
> This program/script was developed with the assistance of an LLM/AI model. I have read and verified all generated content, but there may be areas outside my expertise or potential misunderstandings which could cause errors, risks, or damage. Again, please carefully review the code before executing any script or running any program.
> 
> BR,  
> Author (And my AI Chat :v).

## Prerequisites

### Linux (Ubuntu/WSL/Void)

#### universal (universe repo) (optional)

```SHELL
sudo add-apt-repository universe
```

#### Zsh & Core Utilities
Ensure your system has Zsh and the required networking/text-processing tools installed.

```SHELL
# For WSL-Ubuntu/Ubuntu
sudo apt update
sudo apt install zsh rsync grep gawk -y
```

or 

```SHELL
# For WSL-Void/Void
sudo xbps-install -Suy
sudo xbps-install -Sy zsh rsync grep gawk
```

#### Coder CLI

The script relies on the Coder CLI to establish the SSH tunnel. Ensure it is installed and logged in.

```SHELL
# Ensure your coder config path matches CODER_CFG in the script
coder login <your_coder_url>    # (see your internal document for the guideline.)
coder config-ssh                # (see your internal document for the guideline.)
```

*NOTE*: This script requires a successful SSH connection to the remote Coder server to function!

### Windows 

> NONE

*NOTE*: This script is designed to be executed within a Unix-like environment such as WSL, MSYS2, or Git Bash, writing out to mounted Windows directories.

## Usage/Installation

*Step 1: Configuration*

Before running the script, open it in a text editor and adjust the Configuration variables to match your environment:

- `DEST_DIR`: The local directory where files will be saved (e.g.,`/mnt/c/Users/...`).
- `WORKSPACE`: Your Coder workspace name.
- `BASE`: The root build directory on the remote workspace.
- `PATHS`: The array of specific project build paths to monitor.

*Step 2: Make the script executable*

```SHELL
chmod +x ./CopyBuildFromCoder.sh
```

*Step 3: Execute the script*

```SHELL
./CopyBuildFromCoder.sh
```

## Demonstration / Screenshots

> NONE
