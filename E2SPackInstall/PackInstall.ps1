[CmdletBinding()]
param(
    [switch]$cleanall,
    [string]$dirinternal,
    [string]$zip0,
    [string]$zip1
)

########################################################################################################################
# UTILS
########################################################################################################################
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    switch ($Level) {
        "INFO"    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        "WARN"    { Write-Host "[$timestamp] [WARN] $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
    }
}

function Confirm-UserAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptMessage
    )

    $response = Read-Host "$PromptMessage (y/N)"
    return ($response -eq 'y')
}

function Show-HelpMessage {
    Write-Host @"
Usage:
    .\PackInstall.ps1 [-cleanall] [-dirinternal <path>] [-zip0 <path>] [-zip1 <path>]
Arguments:
    -cleanall       Clean internal target directory before extraction.
    -dirinternal    Path to specified internal target directory.
    -zip0           Path to first pack zip file.
    -zip1           Path to second internal pack zip file.
"@
}

########################################################################################################################
# CONFIG
########################################################################################################################
$DIR_INTERNAL = "C:\Users\phu.nguyen-thanh\.eclipse\com.renesas.platform_1435879475\internal"
$ZIP_PACK0 = "C:\Users\phu.nguyen-thanh\Downloads\FSP_Packs_v6.6.0-rc.0.zip"
$ZIP_PACK1 = "C:\Users\phu.nguyen-thanh\Downloads\FSP_Packs_INTERNAL_v6.6.0-rc.0.zip"
$DIR_EXTRACTED = $env:TEMP

# Override defaults when arguments are supplied.
if ($dirinternal) { $DIR_INTERNAL = $dirinternal }
if ($zip0) { $ZIP_PACK0 = $zip0 }
if ($zip1) { $ZIP_PACK1 = $zip1 }

########################################################################################################################
# ACTION 2: Extract ZIP_PACK0 and verify extracted contents
########################################################################################################################
if (-not (Test-Path -LiteralPath $ZIP_PACK0)) {
    Write-Log "ZIP_PACK0 not found at: $ZIP_PACK0" -Level "ERROR"
    exit 1
}

$baseName0 = [System.IO.Path]::GetFileNameWithoutExtension($ZIP_PACK0)
$extractTarget0 = Join-Path -Path $DIR_EXTRACTED -ChildPath $baseName0

Write-Log "Extracting ZIP_PACK0 to: $extractTarget0"
Expand-Archive -Path $ZIP_PACK0 -DestinationPath $extractTarget0 -Force -ErrorAction Stop

$extractedInternal0 = Join-Path -Path $extractTarget0 -ChildPath "internal"

if (-not (Test-Path -LiteralPath $extractedInternal0 -PathType Container)) {
    Write-Log "Verification failed: '$extractedInternal0' does not exist." -Level "ERROR"
    exit 1
}

Write-Log "Verified ZIP_PACK0 internal structure." -Level "SUCCESS"

########################################################################################################################
# ACTION 1: Clean target internal directory
########################################################################################################################
if ($cleanall) {
    if (Test-Path -LiteralPath $DIR_INTERNAL) {
        Write-Log "Cleaning target directory: $DIR_INTERNAL" -Level "WARN"

        if (Confirm-UserAction "Are you sure you want to clean '$DIR_INTERNAL'?") {
            Remove-Item -Path "$DIR_INTERNAL\*" -Recurse -Force -ErrorAction Stop
            Write-Log "Directory cleaned successfully." -Level "SUCCESS"
        }
        else {
            Write-Log "Skipped cleaning directory upon user request."
        }
    }
    else {
        Write-Log "Directory does not exist, creating new: $DIR_INTERNAL"
        New-Item -ItemType Directory -Path $DIR_INTERNAL -Force | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $DIR_INTERNAL)) {
    New-Item -ItemType Directory -Path $DIR_INTERNAL -Force | Out-Null
}

########################################################################################################################
# ACTION 3: Extract ZIP_PACK1 and verify extracted contents
########################################################################################################################
if (-not (Test-Path -LiteralPath $ZIP_PACK1)) {
    Write-Log "ZIP_PACK1 not found at: $ZIP_PACK1" -Level "ERROR"
    exit 1
}

$baseName1 = [System.IO.Path]::GetFileNameWithoutExtension($ZIP_PACK1)
$extractTarget1 = Join-Path -Path $DIR_EXTRACTED -ChildPath $baseName1

Write-Log "Extracting ZIP_PACK1 to: $extractTarget1"
Expand-Archive -Path $ZIP_PACK1 -DestinationPath $extractTarget1 -Force -ErrorAction Stop

$extractedInternal1 = Join-Path -Path $extractTarget1 -ChildPath "internal"

if (-not (Test-Path -LiteralPath $extractedInternal1 -PathType Container)) {
    Write-Log "Verification failed: '$extractedInternal1' does not exist." -Level "ERROR"
    exit 1
}

Write-Log "Verified ZIP_PACK1 internal structure." -Level "SUCCESS"

########################################################################################################################
# ACTION 4: Copy internal files into target directory
########################################################################################################################
Write-Log "Copying contents from $extractedInternal0 to $DIR_INTERNAL"
Copy-Item -Path "$extractedInternal0\*" -Destination $DIR_INTERNAL -Recurse -Force -ErrorAction Stop

Write-Log "Overwriting contents from $extractedInternal1 to $DIR_INTERNAL"
Copy-Item -Path "$extractedInternal1\*" -Destination $DIR_INTERNAL -Recurse -Force -ErrorAction Stop

Write-Log "All tasks completed successfully." -Level "SUCCESS"