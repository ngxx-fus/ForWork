[CmdletBinding()]
param(
    [switch]$cleanall,
    [string]$dirinternal,
    [string]$zip0,
    [string]$zip1,
    [string]$dirdownloads = $PWD.Path
)

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
    .\PackInstall.ps1 [-cleanall] [-dirinternal <path>] [-zip0 <path>] [-zip1 <path>] [-dirdownloads <path>]
Arguments:
    -cleanall       Clean internal target directory before extraction.
    -dirinternal    Path to specified internal target directory.
    -zip0           Path to first pack zip file.
    -zip1           Path to second internal pack zip file.
    -dirdownloads   Directory to save downloaded files.
"@
}

########################################################################################################################
# CONFIG
########################################################################################################################
$BASE_URL = "https://artifactory.global.renesas.com/artifactory/fsp-ra/release/"
$DIR_INTERNAL = "C:\Users\phu.nguyen-thanh\.eclipse\com.renesas.platform_1435879475\internal"
$DIR_EXTRACTED = $env:TEMP
$DIR_DOWNLOADS = $dirdownloads

# Control flow: Override internal directory path if provided.
if ($dirinternal) { 
    $DIR_INTERNAL = $dirinternal 
}

# Control flow: Verify target directory existence and provide fallback.
if (-not (Test-Path -LiteralPath $DIR_INTERNAL)) {
    $currentUserDir = Join-Path -Path $env:USERPROFILE -ChildPath ".eclipse\com.renesas.platform_1435879475\internal"
    
    # Control flow: If current user's directory exists and differs from given path, suggest switching.
    if (($DIR_INTERNAL -ne $currentUserDir) -and (Test-Path -LiteralPath $currentUserDir)) {
        Write-Log "Target directory not found: $DIR_INTERNAL" -Level "WARN"
        
        # Control flow: Ask user if they want to switch to the detected directory.
        if (Confirm-UserAction "Detected valid path for current user: '$currentUserDir'. Switch to it?") {
            $DIR_INTERNAL = $currentUserDir
            Write-Log "Switched target directory to: $DIR_INTERNAL" -Level "SUCCESS"
        }
    }
    
    # Control flow: Final safety check before proceeding.
    if (-not (Test-Path -LiteralPath $DIR_INTERNAL)) {
        Write-Log "Target directory '$DIR_INTERNAL' does not exist! Installation aborted." -Level "ERROR"
        # Jump statement: Exit script due to missing target directory.
        exit 1
    }
}

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
    Write-Log "Fetching release versions from $BASE_URL ..."
    
    # Control flow: Try to fetch webpage content safely.
    try {
        $htmlContent = Invoke-WebRequest -Uri $BASE_URL -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Log "Failed to download webpage: $($_.Exception.Message)" -Level "ERROR"
        # Jump statement: Exit script on download error.
        exit 1
    }

    # Control flow: Parse html content and extract version numbers.
    $versions = [regex]::Matches($htmlContent.Content, 'href="(v\d+\.\d+\.\d+.*?)/"') | 
        ForEach-Object { $_.Groups[1].Value } | 
        Select-Object -Unique

    # Control flow: Ensure at least one version is parsed.
    if ($versions.Count -eq 0) {
        Write-Log "No suitable versions found. Please check Regex or URL access." -Level "ERROR"
        # Jump statement: Exit script if no versions are found.
        exit 1
    }

    Write-Log "Opening fzf to select version..."
    $FSP_VERSION = $versions | fzf --prompt="Select FSP Version: "

    # Control flow: Check if a selection was made via fzf.
    if ([string]::IsNullOrWhiteSpace($FSP_VERSION)) {
        Write-Log "Selection cancelled by user." -Level "WARN"
        # Jump statement: Exit script gracefully if cancelled.
        exit 0
    }

    Write-Log "Selected version: $FSP_VERSION" -Level "SUCCESS"

    $ZIP0_URL = "${BASE_URL}${FSP_VERSION}/packs/FSP_Packs_${FSP_VERSION}.zip"
    $ZIP1_URL = "${BASE_URL}${FSP_VERSION}/packs/FSP_Packs_INTERNAL_${FSP_VERSION}.zip"

    $ZIP_PACK0 = Join-Path -Path $DIR_DOWNLOADS -ChildPath "FSP_Packs_${FSP_VERSION}.zip"
    $ZIP_PACK1 = Join-Path -Path $DIR_DOWNLOADS -ChildPath "FSP_Packs_INTERNAL_${FSP_VERSION}.zip"

    # Control flow: Only download pack 0 if not already present.
    if (-not (Test-Path -LiteralPath $ZIP_PACK0)) {
        Write-Log "Downloading ZIP0 (1/2): $(Split-Path $ZIP_PACK0 -Leaf) -> $ZIP_PACK0"
        Invoke-WebRequest -Uri $ZIP0_URL -OutFile $ZIP_PACK0
    } else {
        Write-Log "ZIP0 already exists, skipping download: $(Split-Path $ZIP_PACK0 -Leaf)"
    }

    # Control flow: Only download pack 1 if not already present.
    if (-not (Test-Path -LiteralPath $ZIP_PACK1)) {
        Write-Log "Downloading ZIP1 (2/2): $(Split-Path $ZIP_PACK1 -Leaf) -> $ZIP_PACK1"
        Invoke-WebRequest -Uri $ZIP1_URL -OutFile $ZIP_PACK1
    } else {
        Write-Log "ZIP1 already exists, skipping download: $(Split-Path $ZIP_PACK1 -Leaf)"
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