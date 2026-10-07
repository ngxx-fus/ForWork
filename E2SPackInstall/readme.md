# FSP Pack Installer

`PackInstall.ps1` downloads (or uses local ZIP files), extracts, and copies both the standard FSP pack and the INTERNAL pack into the `internal` directory of an Eclipse/e² studio environment.

## Prerequisites

* Windows PowerShell 5.1 or PowerShell 7+.
* `fzf` installed and added to your `PATH` if you want to use interactive version selection. `fzf` is not required if **both** `-zip0` and `-zip1` arguments are provided.
* Network access to Artifactory if using the automated download mode.
* Close your IDE before installation to prevent file-in-use errors.

## Default Configuration

* `$BASE_URL`: The Artifactory URL used to fetch the version list and download the packs.
* `$DIR_INTERNAL`: The target installation directory. You should verify and update the hard-coded path in the script to match your local setup.
* `$DIR_EXTRACTED`: The temporary directory for extraction, defaulting to `$env:TEMP`.
* `$DIR_DOWNLOADS`: The directory where downloaded ZIPs are saved. Defaults to the **current working directory** (`$PWD.Path`), which may differ from the script's location.

## Usage

```powershell
.\PackInstall.ps1 [-cleanall] [-dirinternal <path>] [-zip0 <path>] [-zip1 <path>] [-dirdownloads <path>]

```

| Parameter | Description |
| --- | --- |
| `-cleanall` | Prompts for confirmation, then deletes the existing contents of the target directory before extracting and installing. |
| `-dirinternal` | Overrides the default target directory path. |
| `-zip0` | File path to the **standard pack** ZIP. |
| `-zip1` | File path to the **INTERNAL pack** ZIP. |
| `-dirdownloads` | Directory to save the ZIP files during an automated download. This directory must exist before running the script. |

**Note:** The script will only bypass the Artifactory connection and `fzf` selection if **both `-zip0` and `-zip1**` are provided. If only one is provided, the script will fall back to the interactive version selection and automated download mode.

## Examples

### Select Version, Download, and Install

```powershell
.\PackInstall.ps1

```

The script fetches the version list from Artifactory, opens `fzf` for selection, downloads both ZIPs to the current working directory, and installs them.

### Download and Install with `-cleanall`

```powershell
.\PackInstall.ps1 -cleanall

```

The script **downloads the ZIPs first**, prompts for confirmation to clear the target directory, and then proceeds with extraction and installation.

### Install from Local ZIP Files

Replace the paths below with the **actual file paths on your machine**:

```powershell
.\PackInstall.ps1 `
    -zip0 'C:\Downloads\FSP_Packs_v6.6.0-rc.0.zip' `
    -zip1 'C:\Downloads\FSP_Packs_INTERNAL_v6.6.0-rc.0.zip'

```

### Specify Custom Download and Installation Directories

```powershell
New-Item -ItemType Directory -Path 'C:\Packs' -Force | Out-Null

.\PackInstall.ps1 `
    -dirdownloads 'C:\Packs' `
    -dirinternal 'C:\CustomIDE\.eclipse\internal'

```

## Under the Hood

1. If both local ZIP paths are not provided, the script retrieves the version list, prompts the user via `fzf`, and downloads `ZIP0` (standard) and `ZIP1` (INTERNAL). Existing downloaded files will be skipped.
2. If `-cleanall` is passed, the script asks for confirmation before clearing the target directory. If you answer `N` or leave it blank, the script **continues the installation** but skips the deletion step.
3. The script extracts `ZIP0` and then `ZIP1` into subdirectories within `$env:TEMP`. Each ZIP must contain an `internal` folder at its root after extraction.
4. The script copies the `internal` contents of `ZIP0` first, followed by `ZIP1` using `-Force` to overwrite any matching files.

## Limitations and Safety Notes

* **Backup your target directory before using `-cleanall`.** Currently, the script deletes the target directory's contents *before* confirming that both ZIPs extracted successfully. If a ZIP is missing/corrupted or extraction fails, the script cannot automatically restore the deleted data.
* The version selection step relies on the HTML format returned by Artifactory. If the expected `href` patterns change and the regex fails, the automated selection will not work. In this case, download the ZIPs manually and use the `-zip0` and `-zip1` arguments.
* The script does not verify the file integrity of existing ZIPs before skipping downloads.
* Extracted folders in `$env:TEMP` are not automatically deleted by the script. You can inspect or manually delete them when they are no longer needed.