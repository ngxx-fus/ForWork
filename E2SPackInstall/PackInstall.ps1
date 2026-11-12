[CmdletBinding()]
param(
    [switch]$cleanall,
    [string]$dirinternal,
    [string]$zip0,
    [string]$zip1,
    [string]$dirdownloads = (Join-Path -Path $env:TEMP -ChildPath "pack_install"),
    [ValidateSet("release", "manual")]
    [string]$source = "release"
)

########################################################################################################################
# CONFIGURATION & DEFAULT SETTINGS
# Modify these variables to adjust default behavior or override them using script parameters.
########################################################################################################################

# Artifactory base URL endpoints for FSP packs
$BASE_URL_RELEASE = "https://artifactory.global.renesas.com/artifactory/fsp-ra/release/"
$BASE_URL_MANUAL  = "https://artifactory.global.renesas.com/artifactory/fsp-ra/manual/"

# Default source type: 'release' (default) or 'manual'
$SOURCE = $source

# Temporary extraction directory (default: $env:TEMP)
$DIR_EXTRACTED = $env:TEMP

# Directory where downloaded ZIP files will be saved (default: $env:TEMP\pack_install)
# Can be overridden via parameter: -dirdownloads <path>
$DIR_DOWNLOADS = if ($dirdownloads) { $dirdownloads } else { Join-Path -Path $env:TEMP -ChildPath "pack_install" }

# Target internal directory in Eclipse/e2studio (e.g. C:\Users\<user>\.eclipse\com.renesas.platform_<id>\internal)
# If left empty (""), the script will auto-detect the e2studio platform folder matching 'com.renesas.platform_\d+'
# and automatically set $DIR_INTERNAL to "$DIR_E2S_SUPPORT\internal".
# Can be overridden via parameter: -dirinternal <path>
$DIR_INTERNAL = if ($dirinternal) { $dirinternal } else { "" }

# Internal variable storing the auto-detected e2studio platform support directory
$DIR_E2S_SUPPORT = ""

########################################################################################################################
# UTILS
########################################################################################################################

<#
/*
 * @brief Log message to console with timestamp and color.
 * @param Message The text to log.
 * @param Level Severity level (INFO, WARN, ERROR, SUCCESS).
 */
#>
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # Control flow: Check log level and set color accordingly.
    switch ($Level) {
        "INFO"    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "[$timestamp] [WARN] $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
    }
}

<#
/*
 * @brief Ask user for confirmation.
 * @param PromptMessage The prompt to display.
 * @return Boolean True if yes, false otherwise.
 */
#>
function Confirm-UserAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptMessage
    )

    $response = Read-Host "$PromptMessage (y/N)"
    
    # Jump statement: Return evaluation of user response.
    return ($response -eq 'y')
}

<#
/*
 * @brief Print help message for the script.
 */
#>
function Show-HelpMessage {
    Write-Host @"
Usage:
    .\PackInstall.ps1 [-cleanall] [-dirinternal <path>] [-zip0 <path>] [-zip1 <path>] [-dirdownloads <path>] [-source <release|manual>]
Arguments:
    -cleanall       Clean internal target directory before extraction.
    -dirinternal    Path to specified internal target directory (overrides DIR_INTERNAL).
    -zip0           Path to first pack zip file (public pack).
    -zip1           Path to second internal pack zip file (internal pack).
    -dirdownloads   Directory to save downloaded files (default: $env:TEMP\pack_install).
    -source         Source type: 'release' (default) or 'manual'.
"@
}

########################################################################################################################
# TARGET DIRECTORY RESOLUTION & ENVIRONMENT SETUP
########################################################################################################################

# Control flow: Auto-detect E2S support directory and internal path if not explicitly provided.
if ([string]::IsNullOrWhiteSpace($DIR_INTERNAL)) {
    if (-not [string]::IsNullOrWhiteSpace($DIR_E2S_SUPPORT) -and (Test-Path -LiteralPath $DIR_E2S_SUPPORT)) {
        $DIR_INTERNAL = Join-Path -Path $DIR_E2S_SUPPORT -ChildPath "internal"
        Write-Log "Using configured e2studio support directory: $DIR_E2S_SUPPORT" -Level "SUCCESS"
    } else {
        Write-Log "Searching for e2studio support directory..." -Level "INFO"

        $eclipseBase = Join-Path -Path $env:USERPROFILE -ChildPath ".eclipse"
        $foundPlatforms = @()

        if (Test-Path -LiteralPath $eclipseBase) {
            $foundPlatforms = @(Get-ChildItem -Path $eclipseBase -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^com\.renesas\.platform_\d+$' } |
                Select-Object -ExpandProperty FullName)
        }

        if ($foundPlatforms.Count -eq 1) {
            $DIR_E2S_SUPPORT = $foundPlatforms[0]
            $DIR_INTERNAL = Join-Path -Path $DIR_E2S_SUPPORT -ChildPath "internal"
            Write-Log "Auto-detected e2studio support directory: $DIR_E2S_SUPPORT" -Level "SUCCESS"
        } elseif ($foundPlatforms.Count -gt 1) {
            Write-Log "Found multiple e2studio platform directories. Please select one:" -Level "INFO"
            if (Get-Command fzf -ErrorAction SilentlyContinue) {
                $DIR_E2S_SUPPORT = $foundPlatforms | fzf --prompt="Select e2studio platform support directory: "
            } else {
                $DIR_E2S_SUPPORT = $foundPlatforms[0]
            }
            if (-not [string]::IsNullOrWhiteSpace($DIR_E2S_SUPPORT)) {
                $DIR_INTERNAL = Join-Path -Path $DIR_E2S_SUPPORT -ChildPath "internal"
                Write-Log "Selected e2studio support directory: $DIR_E2S_SUPPORT" -Level "SUCCESS"
            }
        } else {
            Write-Log "Could not auto-detect e2studio support directory matching 'com.renesas.platform_\d+'." -Level "WARN"
        }
    }
}

# Control flow: Select base URL based on source parameter.
$BASE_URL = if ($SOURCE -eq "manual") { $BASE_URL_MANUAL } else { $BASE_URL_RELEASE }
Write-Log "Source mode: $SOURCE -> $BASE_URL"

# Control flow: Verify target directory existence and provide fallback.
if ([string]::IsNullOrWhiteSpace($DIR_INTERNAL) -or (-not (Test-Path -LiteralPath $DIR_INTERNAL))) {
    # If DIR_E2S_SUPPORT exists but internal does not, offer to create it
    if ($DIR_E2S_SUPPORT -and (Test-Path -LiteralPath $DIR_E2S_SUPPORT) -and (-not (Test-Path -LiteralPath $DIR_INTERNAL))) {
        if (Confirm-UserAction "Internal directory '$DIR_INTERNAL' does not exist yet. Create it?") {
            New-Item -ItemType Directory -Path $DIR_INTERNAL -Force | Out-Null
            Write-Log "Created target directory: $DIR_INTERNAL" -Level "SUCCESS"
        }
    }

    # Final safety check before proceeding.
    if ([string]::IsNullOrWhiteSpace($DIR_INTERNAL) -or (-not (Test-Path -LiteralPath $DIR_INTERNAL))) {
        if (-not [string]::IsNullOrWhiteSpace($DIR_INTERNAL)) {
            Write-Log "Target directory '$DIR_INTERNAL' does not exist!" -Level "ERROR"
        } else {
            Write-Log "Target internal directory could not be determined automatically!" -Level "ERROR"
        }
        Write-Log "Please update the internal target path in the script (DIR_INTERNAL) or pass a valid path via '-dirinternal <path>'." -Level "WARN"

        # Search for potential existing Renesas platform internal directories to assist user
        $eclipseBase = Join-Path -Path $env:USERPROFILE -ChildPath ".eclipse"
        if (Test-Path -LiteralPath $eclipseBase) {
            $foundDirs = @(Get-ChildItem -Path $eclipseBase -Recurse -Depth 3 -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'internal' } |
                Select-Object -ExpandProperty FullName)

            if ($foundDirs.Count -gt 0) {
                Write-Log "Found potential internal directories on your system:" -Level "INFO"
                foreach ($d in $foundDirs) {
                    Write-Log "  -> $d" -Level "INFO"
                }
            }
        }

        # Jump statement: Exit script due to missing target directory.
        exit 1
    }
}

Write-Log "Target internal directory: $DIR_INTERNAL" -Level "INFO"

########################################################################################################################
# ACTION 0: SELECT & DOWNLOAD PACK
########################################################################################################################

# Control flow: Check if both zip paths are explicitly provided.
if ($zip0 -and $zip1) {
    $ZIP_PACK0 = $zip0
    $ZIP_PACK1 = $zip1
    Write-Log "Using provided local packs:"
    Write-Log "  -> ZIP0: $ZIP_PACK0"
    Write-Log "  -> ZIP1: $ZIP_PACK1"
} else {
    Write-Log "Fetching available entries from $BASE_URL ..."

    # Control flow: Try to fetch webpage content safely.
    try {
        $htmlContent = Invoke-WebRequest -Uri $BASE_URL -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Log "Failed to fetch webpage: $($_.Exception.Message)" -Level "ERROR"
        # Jump statement: Exit script on fetch error.
        exit 1
    }

    if ($source -eq "release") {
        # Control flow: Release mode — parse version folders (e.g. v5.6.0).
        $entries = [regex]::Matches($htmlContent.Content, 'href="(v\d+\.\d+\.\d+.*?)/"') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique

        # Control flow: Ensure at least one version is parsed.
        if ($entries.Count -eq 0) {
            Write-Log "No release versions found. Please check Regex or URL access." -Level "ERROR"
            exit 1
        }

        Write-Log "Opening fzf to select release version..."
        $FSP_VERSION = $entries | fzf --prompt="Select FSP Release Version: "

        # Control flow: Check if a selection was made via fzf.
        if ([string]::IsNullOrWhiteSpace($FSP_VERSION)) {
            Write-Log "Selection cancelled by user." -Level "WARN"
            exit 0
        }

        Write-Log "Selected version: $FSP_VERSION" -Level "SUCCESS"

        $PACK_BASE_URL = "${BASE_URL}${FSP_VERSION}/packs/"

    } else {
        # Control flow: Manual mode — first select branch, then build.
        $branches = [regex]::Matches($htmlContent.Content, 'href="([^"]+?)/"') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -notmatch '^\.' -and $_ -ne '..' } |
            Select-Object -Unique

        # Control flow: Ensure at least one branch is found.
        if ($branches.Count -eq 0) {
            Write-Log "No branches found at manual URL. Please check URL access." -Level "ERROR"
            exit 1
        }

        Write-Log "Opening fzf to select branch..."
        $BRANCH = $branches | fzf --prompt="Select Branch: "

        # Control flow: Check if a branch was selected.
        if ([string]::IsNullOrWhiteSpace($BRANCH)) {
            Write-Log "Branch selection cancelled by user." -Level "WARN"
            exit 0
        }

        Write-Log "Selected branch: $BRANCH" -Level "SUCCESS"

        # Control flow: Fetch build list under selected branch.
        $branchUrl = "${BASE_URL}${BRANCH}/"
        try {
            $branchContent = Invoke-WebRequest -Uri $branchUrl -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Log "Failed to fetch branch page: $($_.Exception.Message)" -Level "ERROR"
            exit 1
        }

        $builds = [regex]::Matches($branchContent.Content, 'href="([^"]+?)/"') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -notmatch '^\.' -and $_ -ne '..' } |
            Select-Object -Unique

        # Control flow: Ensure at least one build is found.
        if ($builds.Count -eq 0) {
            Write-Log "No builds found under branch '$BRANCH'." -Level "ERROR"
            exit 1
        }

        Write-Log "Opening fzf to select build..."
        $BUILD = $builds | fzf --prompt="Select Build: "

        # Control flow: Check if a build was selected.
        if ([string]::IsNullOrWhiteSpace($BUILD)) {
            Write-Log "Build selection cancelled by user." -Level "WARN"
            exit 0
        }

        Write-Log "Selected build: $BUILD" -Level "SUCCESS"

        $FSP_VERSION = "${BRANCH}/${BUILD}"
        $PACK_BASE_URL = "${BASE_URL}${BRANCH}/${BUILD}/packs/"
    }

    # Control flow: Fetch pack listing to find actual zip filenames.
    Write-Log "Fetching pack list from: $PACK_BASE_URL"
    try {
        $packContent = Invoke-WebRequest -Uri $PACK_BASE_URL -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Log "Failed to fetch pack listing: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }

    # Control flow: Extract all zip filenames from pack listing.
    $allZips = [regex]::Matches($packContent.Content, 'href="([^"]*?\.zip)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique

    # Control flow: Separate public pack (ZIP0) and internal pack (ZIP1).
    $zip0Name = $allZips | Where-Object { $_ -notmatch 'INTERNAL' } | Select-Object -First 1
    $zip1Name = $allZips | Where-Object { $_ -match 'INTERNAL' }    | Select-Object -First 1

    # Control flow: Abort if public pack zip is not found.
    if ([string]::IsNullOrWhiteSpace($zip0Name)) {
        Write-Log "Could not find public pack zip at: $PACK_BASE_URL" -Level "ERROR"
        exit 1
    }

    # Control flow: Abort if internal pack zip is not found.
    if ([string]::IsNullOrWhiteSpace($zip1Name)) {
        Write-Log "Could not find internal pack zip at: $PACK_BASE_URL" -Level "ERROR"
        exit 1
    }

    $ZIP0_URL = "${PACK_BASE_URL}${zip0Name}"
    $ZIP1_URL = "${PACK_BASE_URL}${zip1Name}"

    # Control flow: Ensure download directory exists before saving files.
    if (-not (Test-Path -LiteralPath $DIR_DOWNLOADS)) {
        New-Item -ItemType Directory -Path $DIR_DOWNLOADS -Force | Out-Null
    }

    $ZIP_PACK0 = Join-Path -Path $DIR_DOWNLOADS -ChildPath $zip0Name
    $ZIP_PACK1 = Join-Path -Path $DIR_DOWNLOADS -ChildPath $zip1Name

    # Control flow: Only download pack 0 if not already present.
    if (-not (Test-Path -LiteralPath $ZIP_PACK0)) {
        Write-Log "Downloading ZIP0 (1/2): $zip0Name -> $ZIP_PACK0"
        Invoke-WebRequest -Uri $ZIP0_URL -OutFile $ZIP_PACK0
    } else {
        Write-Log "ZIP0 already exists, skipping download: $zip0Name"
    }

    # Control flow: Only download pack 1 if not already present.
    if (-not (Test-Path -LiteralPath $ZIP_PACK1)) {
        Write-Log "Downloading ZIP1 (2/2): $zip1Name -> $ZIP_PACK1"
        Invoke-WebRequest -Uri $ZIP1_URL -OutFile $ZIP_PACK1
    } else {
        Write-Log "ZIP1 already exists, skipping download: $zip1Name"
    }

    Write-Log "Download completed." -Level "SUCCESS"
}

########################################################################################################################
# ACTION 1: Clean target internal directory
########################################################################################################################

# Control flow: Check if cleanall flag is set.
if ($cleanall) {
    Write-Log "Cleaning target directory: $DIR_INTERNAL" -Level "WARN"

    # Control flow: Confirm destructive action with user.
    if (Confirm-UserAction "Are you sure you want to clean '$DIR_INTERNAL'?") {
        Remove-Item -Path "$DIR_INTERNAL\*" -Recurse -Force -ErrorAction Stop
        Write-Log "Directory cleaned successfully." -Level "SUCCESS"
    }
    else {
        Write-Log "Skipped cleaning directory upon user request."
    }
}

########################################################################################################################
# ACTION 2: Extract ZIP_PACK0 and verify extracted contents
########################################################################################################################

# Control flow: Abort if pack 0 zip is missing.
if (-not (Test-Path -LiteralPath $ZIP_PACK0)) {
    Write-Log "ZIP0 not found at: $ZIP_PACK0" -Level "ERROR"
    # Jump statement: Exit script if pack 0 is missing.
    exit 1
}

$baseName0 = [System.IO.Path]::GetFileNameWithoutExtension($ZIP_PACK0)
$extractTarget0 = Join-Path -Path $DIR_EXTRACTED -ChildPath $baseName0

Write-Log "Extracting ZIP0 ($(Split-Path $ZIP_PACK0 -Leaf)) to: $extractTarget0"
Expand-Archive -Path $ZIP_PACK0 -DestinationPath $extractTarget0 -Force -ErrorAction Stop

$extractedInternal0 = Join-Path -Path $extractTarget0 -ChildPath "internal"

# Control flow: Verify the extracted contents structure.
if (-not (Test-Path -LiteralPath $extractedInternal0 -PathType Container)) {
    Write-Log "Verification failed: '$extractedInternal0' does not exist." -Level "ERROR"
    # Jump statement: Exit if verification fails.
    exit 1
}

Write-Log "Verified ZIP0 internal structure." -Level "SUCCESS"

########################################################################################################################
# ACTION 3: Extract ZIP_PACK1 and verify extracted contents
########################################################################################################################

# Control flow: Abort if pack 1 zip is missing.
if (-not (Test-Path -LiteralPath $ZIP_PACK1)) {
    Write-Log "ZIP1 not found at: $ZIP_PACK1" -Level "ERROR"
    # Jump statement: Exit script if pack 1 is missing.
    exit 1
}

$baseName1 = [System.IO.Path]::GetFileNameWithoutExtension($ZIP_PACK1)
$extractTarget1 = Join-Path -Path $DIR_EXTRACTED -ChildPath $baseName1

Write-Log "Extracting ZIP1 ($(Split-Path $ZIP_PACK1 -Leaf)) to: $extractTarget1"
Expand-Archive -Path $ZIP_PACK1 -DestinationPath $extractTarget1 -Force -ErrorAction Stop

$extractedInternal1 = Join-Path -Path $extractTarget1 -ChildPath "internal"

# Control flow: Verify the extracted contents structure for pack 1.
if (-not (Test-Path -LiteralPath $extractedInternal1 -PathType Container)) {
    Write-Log "Verification failed: '$extractedInternal1' does not exist." -Level "ERROR"
    # Jump statement: Exit if verification fails.
    exit 1
}

Write-Log "Verified ZIP1 internal structure." -Level "SUCCESS"

########################################################################################################################
# ACTION 4: Copy internal files into target directory
########################################################################################################################
Write-Log "Copying contents from ZIP0 to $DIR_INTERNAL"
Copy-Item -Path "$extractedInternal0\*" -Destination $DIR_INTERNAL -Recurse -Force -ErrorAction Stop

Write-Log "Overwriting contents from ZIP1 to $DIR_INTERNAL"
Copy-Item -Path "$extractedInternal1\*" -Destination $DIR_INTERNAL -Recurse -Force -ErrorAction Stop

Write-Log "All tasks completed successfully." -Level "SUCCESS"