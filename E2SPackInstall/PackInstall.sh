#!/usr/bin/env bash

########################################################################################################################
# PARAMS
########################################################################################################################

CLEANALL=false
DIR_INTERNAL=""
ZIP0=""
ZIP1=""
DIR_DOWNLOADS="$(pwd)"
SOURCE="release"

usage() {
    cat <<EOF
Usage:
    ./PackInstall.sh [-c] [-d <path>] [-z <path>] [-Z <path>] [-o <path>] [-s <source>]
Arguments:
    -c          Clean internal target directory before extraction.
    -d <path>   Path to specified internal target directory.
    -z <path>   Path to first pack zip file.
    -Z <path>   Path to second internal pack zip file.
    -o <path>   Directory to save downloaded files.
    -s <source> Source type: 'release' (default) or 'manual'.
EOF
}

while getopts ":cd:z:Z:o:s:h" opt; do
    case $opt in
        c) CLEANALL=true ;;
        d) DIR_INTERNAL="$OPTARG" ;;
        z) ZIP0="$OPTARG" ;;
        Z) ZIP1="$OPTARG" ;;
        o) DIR_DOWNLOADS="$OPTARG" ;;
        s) SOURCE="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
    esac
done

########################################################################################################################
# UTILS
########################################################################################################################

# /*
#  * @brief Log message to console with timestamp and color.
#  * @param $1 Message text.
#  * @param $2 Level: INFO, WARN, ERROR, SUCCESS (default: INFO).
#  */
write_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Control flow: Check log level and set color accordingly.
    case "$level" in
        INFO)    echo -e "\033[36m[$timestamp] [INFO] $message\033[0m" ;;
        WARN)    echo -e "\033[33m[$timestamp] [WARN] $message\033[0m" ;;
        ERROR)   echo -e "\033[31m[$timestamp] [ERROR] $message\033[0m" ;;
        SUCCESS) echo -e "\033[32m[$timestamp] [SUCCESS] $message\033[0m" ;;
    esac
}

# /*
#  * @brief Ask user for confirmation.
#  * @param $1 Prompt message.
#  * @return 0 if yes, 1 otherwise.
#  */
confirm_user_action() {
    local prompt="$1"
    read -r -p "$prompt (y/N): " response

    # Jump statement: Return evaluation of user response.
    [[ "$response" == "y" ]]
}

########################################################################################################################
# CONFIG
########################################################################################################################

BASE_URL_RELEASE="https://artifactory.global.renesas.com/artifactory/fsp-ra/release/"
BASE_URL_MANUAL="https://artifactory.global.renesas.com/artifactory/fsp-ra/manual/"
DIR_EXTRACTED="${TMPDIR:-/tmp}"

# Control flow: Set default internal directory if not provided.
if [[ -z "$DIR_INTERNAL" ]]; then
    DIR_INTERNAL="${HOME}/.eclipse/com.renesas.platform_1435879475/internal"
fi

# Control flow: Select base URL based on source parameter.
if [[ "$SOURCE" == "manual" ]]; then
    BASE_URL="$BASE_URL_MANUAL"
else
    BASE_URL="$BASE_URL_RELEASE"
fi

write_log "Source mode: $SOURCE -> $BASE_URL"

# Control flow: Verify target directory existence and provide fallback.
if [[ ! -d "$DIR_INTERNAL" ]]; then
    current_user_dir="${HOME}/.eclipse/com.renesas.platform_1435879475/internal"

    # Control flow: If current user's directory exists and differs from given path, suggest switching.
    if [[ "$DIR_INTERNAL" != "$current_user_dir" ]] && [[ -d "$current_user_dir" ]]; then
        write_log "Target directory not found: $DIR_INTERNAL" "WARN"

        # Control flow: Ask user if they want to switch to the detected directory.
        if confirm_user_action "Detected valid path for current user: '$current_user_dir'. Switch to it?"; then
            DIR_INTERNAL="$current_user_dir"
            write_log "Switched target directory to: $DIR_INTERNAL" "SUCCESS"
        fi
    fi

    # Control flow: Final safety check before proceeding.
    if [[ ! -d "$DIR_INTERNAL" ]]; then
        write_log "Target directory '$DIR_INTERNAL' does not exist! Installation aborted." "ERROR"
        # Jump statement: Exit script due to missing target directory.
        exit 1
    fi
fi

########################################################################################################################
# ACTION 0: SELECT & DOWNLOAD PACK
########################################################################################################################

# Control flow: Check if both zip paths are explicitly provided.
if [[ -n "$ZIP0" ]] && [[ -n "$ZIP1" ]]; then
    ZIP_PACK0="$ZIP0"
    ZIP_PACK1="$ZIP1"
    write_log "Using provided local packs:"
    write_log "  -> ZIP0: $ZIP_PACK0"
    write_log "  -> ZIP1: $ZIP_PACK1"
else
    write_log "Fetching available entries from $BASE_URL ..."

    # Control flow: Try to fetch webpage content safely.
    html_content="$(curl -fsSL "$BASE_URL" 2>&1)"
    if [[ $? -ne 0 ]]; then
        write_log "Failed to fetch webpage: $html_content" "ERROR"
        # Jump statement: Exit script on fetch error.
        exit 1
    fi

    if [[ "$SOURCE" == "release" ]]; then
        # Control flow: Release mode — parse version folders (e.g. v5.6.0).
        mapfile -t entries < <(echo "$html_content" | grep -oP 'href="\Kv\d+\.\d+\.\d+[^"/]*(?=/)' | sort -u)

        # Control flow: Ensure at least one version is parsed.
        if [[ ${#entries[@]} -eq 0 ]]; then
            write_log "No release versions found. Please check Regex or URL access." "ERROR"
            exit 1
        fi

        write_log "Opening fzf to select release version..."
        FSP_VERSION="$(printf '%s\n' "${entries[@]}" | fzf --prompt="Select FSP Release Version: ")"

        # Control flow: Check if a selection was made via fzf.
        if [[ -z "$FSP_VERSION" ]]; then
            write_log "Selection cancelled by user." "WARN"
            # Jump statement: Exit script gracefully if cancelled.
            exit 0
        fi

        write_log "Selected version: $FSP_VERSION" "SUCCESS"
        PACK_BASE_URL="${BASE_URL}${FSP_VERSION}/packs/"

    else
        # Control flow: Manual mode — first select branch, then build.
        mapfile -t branches < <(echo "$html_content" | grep -oP 'href="\K[^"./][^"/]*(?=/)' | grep -v '^\.\.' | sort -u)

        # Control flow: Ensure at least one branch is found.
        if [[ ${#branches[@]} -eq 0 ]]; then
            write_log "No branches found at manual URL. Please check URL access." "ERROR"
            exit 1
        fi

        write_log "Opening fzf to select branch..."
        BRANCH="$(printf '%s\n' "${branches[@]}" | fzf --prompt="Select Branch: ")"

        # Control flow: Check if a branch was selected.
        if [[ -z "$BRANCH" ]]; then
            write_log "Branch selection cancelled by user." "WARN"
            exit 0
        fi

        write_log "Selected branch: $BRANCH" "SUCCESS"

        # Control flow: Fetch build list under selected branch.
        branch_url="${BASE_URL}${BRANCH}/"
        branch_content="$(curl -fsSL "$branch_url" 2>&1)"
        if [[ $? -ne 0 ]]; then
            write_log "Failed to fetch branch page: $branch_content" "ERROR"
            exit 1
        fi

        mapfile -t builds < <(echo "$branch_content" | grep -oP 'href="\K[^"./][^"/]*(?=/)' | grep -v '^\.\.' | sort -u)

        # Control flow: Ensure at least one build is found.
        if [[ ${#builds[@]} -eq 0 ]]; then
            write_log "No builds found under branch '$BRANCH'." "ERROR"
            exit 1
        fi

        write_log "Opening fzf to select build..."
        BUILD="$(printf '%s\n' "${builds[@]}" | fzf --prompt="Select Build: ")"

        # Control flow: Check if a build was selected.
        if [[ -z "$BUILD" ]]; then
            write_log "Build selection cancelled by user." "WARN"
            exit 0
        fi

        write_log "Selected build: $BUILD" "SUCCESS"

        FSP_VERSION="${BRANCH}/${BUILD}"
        PACK_BASE_URL="${BASE_URL}${BRANCH}/${BUILD}/packs/"
    fi

    # Control flow: Fetch pack listing to find actual zip filenames.
    write_log "Fetching pack list from: $PACK_BASE_URL"
    pack_content="$(curl -fsSL "$PACK_BASE_URL" 2>&1)"
    if [[ $? -ne 0 ]]; then
        write_log "Failed to fetch pack listing: $pack_content" "ERROR"
        exit 1
    fi

    # Control flow: Extract all zip filenames from pack listing.
    mapfile -t all_zips < <(echo "$pack_content" | grep -oP 'href="\K[^"]*?\.zip(?=")' | sort -u)

    # Control flow: Separate public pack (ZIP0) and internal pack (ZIP1).
    zip0_name="$(printf '%s\n' "${all_zips[@]}" | grep -v 'INTERNAL' | head -1)"
    zip1_name="$(printf '%s\n' "${all_zips[@]}" | grep 'INTERNAL'    | head -1)"

    # Control flow: Abort if public pack zip is not found.
    if [[ -z "$zip0_name" ]]; then
        write_log "Could not find public pack zip at: $PACK_BASE_URL" "ERROR"
        exit 1
    fi

    # Control flow: Abort if internal pack zip is not found.
    if [[ -z "$zip1_name" ]]; then
        write_log "Could not find internal pack zip at: $PACK_BASE_URL" "ERROR"
        exit 1
    fi

    ZIP0_URL="${PACK_BASE_URL}${zip0_name}"
    ZIP1_URL="${PACK_BASE_URL}${zip1_name}"

    ZIP_PACK0="${DIR_DOWNLOADS}/${zip0_name}"
    ZIP_PACK1="${DIR_DOWNLOADS}/${zip1_name}"

    # Control flow: Only download pack 0 if not already present.
    if [[ ! -f "$ZIP_PACK0" ]]; then
        write_log "Downloading ZIP0 (1/2): $zip0_name -> $ZIP_PACK0"
        curl -fL "$ZIP0_URL" -o "$ZIP_PACK0"
    else
        write_log "ZIP0 already exists, skipping download: $zip0_name"
    fi

    # Control flow: Only download pack 1 if not already present.
    if [[ ! -f "$ZIP_PACK1" ]]; then
        write_log "Downloading ZIP1 (2/2): $zip1_name -> $ZIP_PACK1"
        curl -fL "$ZIP1_URL" -o "$ZIP_PACK1"
    else
        write_log "ZIP1 already exists, skipping download: $zip1_name"
    fi

    write_log "Download completed." "SUCCESS"
fi

########################################################################################################################
# ACTION 1: Clean target internal directory
########################################################################################################################

# Control flow: Check if cleanall flag is set.
if [[ "$CLEANALL" == true ]]; then
    write_log "Cleaning target directory: $DIR_INTERNAL" "WARN"

    # Control flow: Confirm destructive action with user.
    if confirm_user_action "Are you sure you want to clean '$DIR_INTERNAL'?"; then
        rm -rf "${DIR_INTERNAL:?}"/*
        write_log "Directory cleaned successfully." "SUCCESS"
    else
        write_log "Skipped cleaning directory upon user request."
    fi
fi

########################################################################################################################
# ACTION 2: Extract ZIP_PACK0 and verify extracted contents
########################################################################################################################

# Control flow: Abort if pack 0 zip is missing.
if [[ ! -f "$ZIP_PACK0" ]]; then
    write_log "ZIP0 not found at: $ZIP_PACK0" "ERROR"
    # Jump statement: Exit script if pack 0 is missing.
    exit 1
fi

base_name0="$(basename "$ZIP_PACK0" .zip)"
extract_target0="${DIR_EXTRACTED}/${base_name0}"

write_log "Extracting ZIP0 ($(basename "$ZIP_PACK0")) to: $extract_target0"
unzip -o "$ZIP_PACK0" -d "$extract_target0"

extracted_internal0="${extract_target0}/internal"

# Control flow: Verify the extracted contents structure.
if [[ ! -d "$extracted_internal0" ]]; then
    write_log "Verification failed: '$extracted_internal0' does not exist." "ERROR"
    # Jump statement: Exit if verification fails.
    exit 1
fi

write_log "Verified ZIP0 internal structure." "SUCCESS"

########################################################################################################################
# ACTION 3: Extract ZIP_PACK1 and verify extracted contents
########################################################################################################################

# Control flow: Abort if pack 1 zip is missing.
if [[ ! -f "$ZIP_PACK1" ]]; then
    write_log "ZIP1 not found at: $ZIP_PACK1" "ERROR"
    # Jump statement: Exit script if pack 1 is missing.
    exit 1
fi

base_name1="$(basename "$ZIP_PACK1" .zip)"
extract_target1="${DIR_EXTRACTED}/${base_name1}"

write_log "Extracting ZIP1 ($(basename "$ZIP_PACK1")) to: $extract_target1"
unzip -o "$ZIP_PACK1" -d "$extract_target1"

extracted_internal1="${extract_target1}/internal"

# Control flow: Verify the extracted contents structure for pack 1.
if [[ ! -d "$extracted_internal1" ]]; then
    write_log "Verification failed: '$extracted_internal1' does not exist." "ERROR"
    # Jump statement: Exit if verification fails.
    exit 1
fi

write_log "Verified ZIP1 internal structure." "SUCCESS"

########################################################################################################################
# ACTION 4: Copy internal files into target directory
########################################################################################################################

write_log "Copying contents from ZIP0 to $DIR_INTERNAL"
cp -rf "${extracted_internal0}/." "$DIR_INTERNAL"

write_log "Overwriting contents from ZIP1 to $DIR_INTERNAL"
cp -rf "${extracted_internal1}/." "$DIR_INTERNAL"

write_log "All tasks completed successfully." "SUCCESS"