#!/usr/bin/env bash

###############################################################################
# Setup script for Coder workspace (Ubuntu-based)
# - Install Zsh and set as default shell
# - Install Neovim + custom config
# - Install Oh-My-Zsh + plugins + custom theme
# - Install user aliases
# - Install SEGGER J-Link tools
# - Setup desktop background wallpaper
# - Install Clangd
# - Install custom APT packages
# - Install Nerd Fonts (Full Pack ~ 1.5GB)
#
# Usage: bash CoderCustomSetup_V2.sh
###############################################################################

set -e  # Exit immediately on error
set -u  # Treat unset variables as error

# ===========================================================================
# Global config flags (set to 1 to enable, 0 to skip)
# ===========================================================================
export SETUP_OHMYZSH_EN=1
export SETUP_NVIM_EN=1
export SETUP_NVIM_PREREQUISITES_EN=1        # only works if SETUP_NVIM_EN=1
export SETUP_ADD_APT_REPO_EN=1
export SETUP_USER_ALIASES_EN=1
export SETUP_BACKGROUND_EN=1
export SETUP_AUTO_SET_BACKGROUND_EN=1       # only works if SETUP_BACKGROUND_EN=1
export SETUP_CLANGD_EN=1
export SETUP_JLINK_V950_EN=1
export SETUP_JLINK_V950_ARM_EN=1
export SETUP_JLINK_V970_EN=1
export SETUP_JLINK_V970_ARM_EN=1
export SETUP_NERD_FONTS_EN=1                # enable Nerd Fonts full pack installation

export SETUP_CONN_CHECK_EN=1
export SETUP_VALID_FILE_CHECK_FILE_EN=0     # temporarily not implemented/active

export SETUP_APT_INSTALL_LIST_EN=1
export SETUP_APT_INSTALL_LIST=(
    "btop" "tree" "duf" "tmux"
)

export SETUP_HCMC_TIME_EN=1

# ===========================================================================
# Global private vars
# ===========================================================================

export NVIM_VERSION="nightly"
export NVIM_TARBALL="nvim-linux-x86_64.tar.gz"
export NIVM_INSTALL_DIRNAME="nvim-linux-x86_64"
export BACKGROUND_IMG_FILENAME="IMG_4273.JPG"
export CLANGD_VERSION="22.1.6"
export CLANGD_ZIP_FILENAME="clangd-linux-22.1.6.zip"
export CLANGD_EXTRACTED_FILENAME="clangd-linux-22.1.6"

export FOLDER_CURRENT=$(pwd)
export FOLDER_HOME="/home/coder"
export FOLDER_WORKSPACE="${FOLDER_HOME}/workspace"
export FOLDER_DOWNLOADS="${FOLDER_HOME}/Downloads"
export FOLDER_DOT_ZSHRC="${FOLDER_HOME}/.zshrc"
export FOLDER_DOT_OH_MY_ZSH="${FOLDER_HOME}/.oh-my-zsh"
export FOLDER_NVIM_CONFIG="${FOLDER_HOME}/.config/nvim"
export FOLDER_FUS="${FOLDER_HOME}/.fus"
export FOLDER_BACKGROUND="${FOLDER_FUS}/.BG"
export FILE_USER_ALIASES="${FOLDER_FUS}/user_aliases.sh"
export FOLDER_CLANGD="/opt/clangd"
export FOLDER_OMZ_THEMES="${FOLDER_DOT_OH_MY_ZSH}/themes"
export FILE_NGXXFUS_THEME="${FOLDER_OMZ_THEMES}/ngxxfus.zsh-theme"

# JLink specific variables
export URL_JLINK_ARCHIVES="https://github.com/ngxx-fus/ForWork/releases/download"
export FOLDER_JLINK_COMM_DEST="${FOLDER_WORKSPACE}"

export TAG_ARCHIVE_JLINK_V970="Cloned-JLink-V970"
export FILE_ZIP_JLINK_V970="JLink_Linux_V970_x86_64.tgz"
export FILE_ZIP_JLINK_V970_ARM="JLink_Linux_V970_arm64.tgz"
export FOLDER_JLINK_V970_DEST="JLink_V970"
export FOLDER_JLINK_V970_ARM_DEST="JLink_V970_Arm"

export TAG_ARCHIVE_JLINK_V950="Cloned-JLink-V950"
export FILE_ZIP_JLINK_V950="JLink_Linux_V950_x86_64.tgz"
export FILE_ZIP_JLINK_V950_ARM="JLink_Linux_V950_arm64.tgz"
export FOLDER_JLINK_V950_DEST="JLink_V950"
export FOLDER_JLINK_V950_ARM_DEST="JLink_V950_Arm"

# URLs
export URL_FORWORK_ROOTDIR="https://raw.githubusercontent.com/ngxx-fus/ForWork/refs/heads/main"
export URL_USER_ALIASES="${URL_FORWORK_ROOTDIR}/.assert/useralias.sh"
export URL_NGXXFUS_THEME="${URL_FORWORK_ROOTDIR}/.assert/ngxxfus.zsh-theme"
export URL_BACKGROUND_IMG="${URL_FORWORK_ROOTDIR}/.imgs/BG/IMG_4273.JPG"
export URL_NVIM_DOWNLOAD="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TARBALL}"
export URL_NEOVIM_CONF_REPO="https://github.com/ngxx-fus/neovim-conf.git"
export URL_OHMYZSH_INSTALL_SCRIPT="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
export URL_ZSH_SYNTAX_HIGHLIGHTING_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
export URL_ZSH_AUTOSUGGESTIONS_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
export URL_ZSH_Z_REPO="https://github.com/agkozak/zsh-z.git"
export URL_CLANGD="https://github.com/clangd/clangd/releases/download/${CLANGD_VERSION}/${CLANGD_ZIP_FILENAME}"

# Nerd Fonts specific variables
export URL_NERD_FONTS_REPO="https://github.com/ryanoasis/nerd-fonts.git"
export FOLDER_NERD_FONTS="${FOLDER_DOWNLOADS}/nerd-fonts"

# ===========================================================================
# Helper functions
# ===========================================================================

# /*
#  * @brief Ensure the given directory exists, creating it if needed.
#  * @param $1 Path to the directory to create.
#  * @return 0 if directory exists or created successfully.
#  * @return 1 if wrong number of arguments or failed to create.
#  */
MakeThisDirExist() {
    # Check if number of arguments is not equal to 1
    if [[ $# -ne 1 ]]; then
        echo "[ERR][MakeThisDirExist] Wrong number of args (expected 1, got $#)"
        # Return error code for invalid arguments
        return 1
    fi

    local target_dir="$1"

    # Check if directory already exists
    if [ -d "${target_dir}" ]; then
        # Return success as directory is present
        return 0
    fi

    # Check if directory creation succeeds
    if mkdir -p "${target_dir}"; then
        echo "[INF][MakeThisDirExist] Created: '${target_dir}'"
        # Return success after creation
        return 0
    else
        echo "[ERR][MakeThisDirExist] Failed to create: '${target_dir}'"
        # Return error code for failure to create directory
        return 1
    fi
}

# /*
#  * @brief Append a line to a file only if it does not already exist.
#  * @param $1 Target file path.
#  * @param $2 Line to append.
#  * @return 0 if appended or line already exists.
#  * @return 1 if wrong number of arguments.
#  */
AppendIfNotExist() {
    # Check if number of arguments is not equal to 2
    if [[ $# -ne 2 ]]; then
        echo "[ERR][AppendIfNotExist] Wrong number of args (expected 2, got $#)"
        # Return error code for invalid arguments
        return 1
    fi

    local target_file="$1"
    local line="$2"

    # Check if line does not exist in file
    if ! grep -qF "${line}" "${target_file}" 2>/dev/null; then
        echo "${line}" >> "${target_file}"
        echo "[INF][AppendIfNotExist] Appended to ${target_file}: ${line}"
    else
        echo "[INF][AppendIfNotExist] Already exists, skipping: ${line}"
    fi

    # Return success
    return 0
}

# /*
#  * @brief Extract base filename located after the last slash and before the last dot.
#  * @param $1 Input path string.
#  * @return 0 if extracted basename successfully.
#  * @return 1 if invalid path format.
#  */
GetBaseName() {
    local path="$1"

    # Check if path is empty or has trailing slash
    if [ -z "$path" ] || [ "${path%[/\\]}" != "$path" ]; then
        # Return error code for invalid path
        return 1
    fi

    local filename="${path##*[/\\]}"

    # Check if filename has no extension
    if [ "$filename" = "${filename%.*}" ]; then
        # Return error code for missing extension
        return 1
    fi

    local basename="${filename%.*}"
    printf '%s\n' "$basename"

    # Return success
    return 0
}

# /*
#  * @brief Check if the provided URL is reachable.
#  * @param $1 Target web address.
#  * @return 0 if target reachable or feature disabled.
#  * @return 1 if missing argument or target unreachable.
#  */
PerformConnectionCheck() {
    # Check if number of arguments is not equal to 1
    if [[ $# -ne 1 ]]; then
        echo "[ERR][PerformConnectionCheck] Missing URL argument."
        # Return error code for missing argument
        return 1
    fi

    local target_url="$1"

    # Check if connection check feature is disabled
    if [[ "${SETUP_CONN_CHECK_EN}" != "1" ]]; then
        # Return success as check is disabled
        return 0
    fi

    echo "[INF][PerformConnectionCheck] Testing connection to: ${target_url}"
    # Check if curl head request succeeds
    if curl --output /dev/null --silent --head --fail --location "${target_url}"; then
        echo "[INF][PerformConnectionCheck] Connection OK."
        # Return success for reachable URL
        return 0
    else
        # Return error code for unreachable URL
        return 1
    fi
}

# /*
#  * @brief Check if the provided URL downloads an actual file rather than HTML.
#  * @param $1 Target web address.
#  * @return 0 if valid file format or feature disabled.
#  * @return 1 if missing argument or returned HTML page.
#  */
PerformDownloadCheck() {
    # Check if number of arguments is not equal to 1
    if [[ $# -ne 1 ]]; then
        echo "[ERR][PerformDownloadCheck] Missing URL argument."
        # Return error code for missing argument
        return 1
    fi

    local target_url="$1"

    # Check if valid file check feature is disabled
    if [[ "${SETUP_VALID_FILE_CHECK_FILE_EN}" != "1" ]]; then
        # Return success as check is disabled
        return 0
    fi

    echo "[INF][PerformDownloadCheck] Validating file type for: ${target_url}"
    local content_type
    
    content_type=$(curl -sI -L "${target_url}" | grep -i -E "^Content-Type:" | tail -n 1)

    # Check if content type contains text/html
    if echo "${content_type}" | grep -q -i "text/html"; then
        echo "[ERR][PerformDownloadCheck] URL returned HTML instead of a valid file!"
        # Return error code for invalid file format
        return 1
    else
        echo "[INF][PerformDownloadCheck] File format OK."
        # Return success for valid format
        return 0
    fi
}

# /*
#  * @brief Download, extract, and install a specific JLink version.
#  * @param $1 Installation enable flag (1 to run, 0 to skip).
#  * @param $2 GitHub release tag.
#  * @param $3 Archive file name (e.g., .tgz).
#  * @param $4 Destination folder name inside workspace.
#  * @return 0 on success or skipped.
#  * @return 1 on network, file format, or extraction error.
#  */
InstallJLinkVersion() {
    local enable_flag="$1"
    local tag_name="$2"
    local file_name="$3"
    local dest_name="$4"

    # Check if installation is disabled
    if [[ "${enable_flag}" != "1" ]]; then
        # Return success as feature is disabled
        return 0
    fi

    local dest_path="${FOLDER_JLINK_COMM_DEST}/${dest_name}"
    
    # Check if already installed to ensure idempotency
    if [ -d "${dest_path}" ]; then
        echo "[INF] ${dest_name} is already installed in ${dest_path}. Skipping."
        # Return success as it is already installed
        return 0
    fi

    echo ">>> Installing ${dest_name}..."

    final_url="${URL_JLINK_ARCHIVES}/${tag_name}/${file_name}"
    
    # Check network connection
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping ${dest_name}."
        # Return error due to connection failure
        return 1
    # Check valid download file format
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping ${dest_name}."
        # Return error due to invalid file type
        return 1
    else
        local extracted_folder="${file_name%.*}"

        MakeThisDirExist "${FOLDER_JLINK_COMM_DEST}"
        cd "${FOLDER_DOWNLOADS}"

        # Check if file is not already downloaded
        if [ ! -f "${file_name}" ]; then
            echo "[INF] Downloading ${file_name}..."
            wget -q --show-progress "${final_url}" -O "${file_name}"
        else
            echo "[INF] File ${file_name} already downloaded. Skipping download."
        fi

        # Check if archive exists before extraction
        if [ -f "${file_name}" ]; then
            echo "[INF] Extracting ${file_name}..."
            tar -zxvf "${file_name}"

            # Check if extraction created the expected folder
            if [ -d "${extracted_folder}" ]; then
                echo "[INF] Moving ${extracted_folder} to ${dest_path}"
                mv "${extracted_folder}" "${dest_path}"
                
                rm -f "${file_name}"
                echo "[INF] ${dest_name} installation successful."

                echo "[INF] Adding ${dest_name} to system PATH in ${FOLDER_DOT_ZSHRC}..."
                AppendIfNotExist "${FOLDER_DOT_ZSHRC}" ""
                AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "# JLINK ${dest_name} ###################################"
                AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "export PATH=\"\$PATH:${dest_path}\""
            else
                echo "[ERR] Extracted folder ${extracted_folder} not found."
            fi
        else
            echo "[ERR] Failed to download from ${final_url}"
        fi

        cd "${FOLDER_CURRENT}"
    fi

    # Return success
    return 0
}

# ===========================================================================
# Pre-flight Checks
# ===========================================================================
echo ">>> Running pre-flight checks..."

# Check if user has sudo privileges without password prompt
if ! sudo -n true 2>/dev/null; then
    echo "[ERR] Sudo requires a password. Please run in an environment with passwordless sudo or authenticate first."
    # Exit with error status
    exit 1
fi

# ===========================================================================
# Check and Install Zsh, Set as Default
# ===========================================================================
echo ">>> Checking for zsh..."

# Check if zsh command does not exist
if ! command -v zsh >/dev/null 2>&1; then
    echo "[INF] zsh not found. Installing zsh..."
    export DEBIAN_FRONTEND=noninteractive
    sudo add-apt-repository universe -y
    sudo apt update -y
    sudo apt install -y zsh
else
    echo "[INF] zsh is already installed."
fi

# Check if current default shell is not zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "[INF] Switching default shell to zsh..."
    sudo chsh -s "$(which zsh)" "$(whoami)"
else
    echo "[INF] zsh is already the default shell."
fi

# ===========================================================================
# Pre-create required directories
# ===========================================================================
MakeThisDirExist "${FOLDER_CURRENT}"
MakeThisDirExist "$(dirname "${FOLDER_DOT_ZSHRC}")"
MakeThisDirExist "${FOLDER_DOWNLOADS}"
MakeThisDirExist "${FOLDER_FUS}"

# ===========================================================================
# Add repository & Install APT Packages
# ===========================================================================
# Check if APT repository addition is enabled
if [[ "${SETUP_ADD_APT_REPO_EN}" == "1" ]]; then
    echo ">>> Updating apt repositories..."
    export DEBIAN_FRONTEND=noninteractive
    sudo add-apt-repository universe -y
    sudo apt update -y
fi

# Check if custom APT installation list is enabled
if [[ "${SETUP_APT_INSTALL_LIST_EN}" == "1" ]]; then
    echo ">>> Installing custom APT packages..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y "${SETUP_APT_INSTALL_LIST[@]}"
fi

# ===========================================================================
# Install Neovim
# ===========================================================================
# Check if Neovim setup is enabled
if [[ "${SETUP_NVIM_EN}" == "1" ]]; then
    # Check if Neovim is already installed
    if [ -x /usr/local/bin/nvim ] && [ -d /opt/nvim ]; then
        echo "[INF] Neovim is already installed. Skipping installation."
    else
        echo ">>> Installing Neovim (${NVIM_VERSION})..."
        
        final_url="${URL_NVIM_DOWNLOAD}"
        
        # Check network connection
        if ! PerformConnectionCheck "${final_url}"; then
            echo "[ERR] Failed to connect to ${final_url}. Skipping Neovim."
        # Check valid download file format
        elif ! PerformDownloadCheck "${final_url}"; then
            echo "[ERR] Invalid file format at ${final_url}. Skipping Neovim."
        else
            # Check if prerequisites installation is enabled
            if [[ "${SETUP_NVIM_PREREQUISITES_EN}" == "1" ]]; then 
                echo "[INF] Installing Neovim prerequisites..."
                export DEBIAN_FRONTEND=noninteractive
                sudo apt update && sudo apt install -y \
                    git build-essential gcc g++ make ripgrep fd-find unzip curl \
                    tar nodejs npm python3 python3-pip xclip wl-clipboard

                MakeThisDirExist "${FOLDER_HOME}/.local/bin"
                # Check if fdfind exists but fd is missing
                if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
                    ln -sf "$(which fdfind)" "${FOLDER_HOME}/.local/bin/fd"
                    echo "[INF] Created symlink for fd -> fdfind in ~/.local/bin"
                fi
            fi

            cd "${FOLDER_DOWNLOADS}"
            
            # Check if tarball is not downloaded
            if [ ! -f "${NVIM_TARBALL}" ]; then
                echo "[INF] Downloading Neovim tarball..."
                wget -q --show-progress "${final_url}" -O "${NVIM_TARBALL}"
            else
                echo "[INF] Neovim tarball already downloaded. Skipping download."
            fi

            echo "[INF] Extracting ${NVIM_TARBALL}..."
            tar -zxvf "${NVIM_TARBALL}"

            # Check for existing /opt/nvim directory and backup
            if [ -d /opt/nvim ]; then
                sudo cp -vrf /opt/nvim "/opt/nvim.bak.$(date +%s)"
                sudo rm -rf /opt/nvim
                echo "[INF] Backed up old /opt/nvim"
            fi
            
            # Check for existing symlink and remove
            if [ -e /usr/local/bin/nvim ]; then
                sudo rm -vf /usr/local/bin/nvim 
                echo "[INF] Removed existing /usr/local/bin/nvim"
            fi

            sudo mkdir -p /opt/nvim
            sudo cp -vrf "${NIVM_INSTALL_DIRNAME}/." /opt/nvim

            sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
            echo "[INF] Created symlink /usr/local/bin/nvim -> /opt/nvim/bin/nvim"

            # Check if custom neovim config exists and backup
            if [ -d "${FOLDER_NVIM_CONFIG}" ]; then
                mv "${FOLDER_NVIM_CONFIG}" "${FOLDER_NVIM_CONFIG}.bak.$(date +%s)"
                echo "[INF] Backed up old Neovim config"
            fi
            MakeThisDirExist "${FOLDER_NVIM_CONFIG}"

            echo "[INF] Cloning Neovim configuration repository..."
            git clone --recurse-submodules \
                "${URL_NEOVIM_CONF_REPO}" \
                "${FOLDER_NVIM_CONFIG}"

            rm -rf "${NVIM_TARBALL}" "./${NIVM_INSTALL_DIRNAME}"
            cd "${FOLDER_CURRENT}"
            echo ">>> Neovim installed successfully."
        fi
    fi
fi

# ===========================================================================
# Install Oh-My-Zsh + plugins + custom theme
# ===========================================================================
# Check if Oh-My-Zsh setup is enabled
if [[ "${SETUP_OHMYZSH_EN}" == "1" ]]; then
    # Check if Oh-My-Zsh is already installed
    if [ -d "${FOLDER_DOT_OH_MY_ZSH}" ]; then
        echo "[INF] Oh-My-Zsh is already installed. Skipping setup."
    else
        echo ">>> Installing Oh-My-Zsh..."

        # Check if existing .zshrc exists and backup
        if [ -f "${FOLDER_DOT_ZSHRC}" ]; then
            cp -vf "${FOLDER_DOT_ZSHRC}" "${FOLDER_DOT_ZSHRC}.bak"
            echo ">>> Backed up .zshrc → .zshrc.bak"
        fi

        final_url="${URL_OHMYZSH_INSTALL_SCRIPT}"
        
        # Check network connection
        if ! PerformConnectionCheck "${final_url}"; then
            echo "[ERR] Failed to connect to ${final_url}. Skipping Oh-My-Zsh installer."
        # Check valid download file format
        elif ! PerformDownloadCheck "${final_url}"; then
            echo "[ERR] Invalid file format at ${final_url}. Skipping Oh-My-Zsh installer."
        else
            OMZ_INSTALLER="${FOLDER_DOWNLOADS}/omz_install.sh"
            
            # Check if OMZ installer is not downloaded
            if [ ! -f "${OMZ_INSTALLER}" ]; then
                curl -fsSL "${final_url}" -o "${OMZ_INSTALLER}"
            fi
            
            sh "${OMZ_INSTALLER}" "" --unattended

            export ZSH_CUSTOM="${FOLDER_DOT_OH_MY_ZSH}/custom"

            # Check if zsh-syntax-highlighting plugin exists
            if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
                git clone "${URL_ZSH_SYNTAX_HIGHLIGHTING_REPO}" "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
            fi

            # Check if zsh-autosuggestions plugin exists
            if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
                git clone "${URL_ZSH_AUTOSUGGESTIONS_REPO}" "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
            fi

            # Check if zsh-z plugin exists
            if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-z" ]; then
                git clone "${URL_ZSH_Z_REPO}" "${ZSH_CUSTOM}/plugins/zsh-z"
            fi

            sed -i \
                's/^plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-z)/' \
                "${FOLDER_DOT_ZSHRC}"

            echo ">>> Installing ngxxfus theme..."
            MakeThisDirExist "${FOLDER_OMZ_THEMES}"

            theme_url="${URL_NGXXFUS_THEME}"
            
            # Check network connection for theme
            if ! PerformConnectionCheck "${theme_url}"; then
                echo "[ERR] Failed to connect to ${theme_url}. Skipping theme setup."
            # Check valid download file format for theme
            elif ! PerformDownloadCheck "${theme_url}"; then
                echo "[ERR] Invalid file format at ${theme_url}. Skipping theme setup."
            else
                wget -q --show-progress -O "${FILE_NGXXFUS_THEME}" "${theme_url}"

                # Check if ZSH_THEME is already defined
                if grep -q '^ZSH_THEME=' "${FOLDER_DOT_ZSHRC}"; then
                    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="ngxxfus"/' "${FOLDER_DOT_ZSHRC}"
                else
                    AppendIfNotExist "${FOLDER_DOT_ZSHRC}" 'ZSH_THEME="ngxxfus"'
                fi
            fi

            # Check if backup .zshrc exists to restore custom configs
            if [ -f "${FOLDER_DOT_ZSHRC}.bak" ]; then
                printf "\n\n\n#### ORIGINAL .ZSHRC ####\n\n\n" >> "${FOLDER_DOT_ZSHRC}"
                cat "${FOLDER_DOT_ZSHRC}.bak" >> "${FOLDER_DOT_ZSHRC}"
            fi

            sed -i 's/^autoload -Uz promptinit/# autoload -Uz promptinit/' "${FOLDER_DOT_ZSHRC}"
            sed -i 's/^promptinit/# promptinit/' "${FOLDER_DOT_ZSHRC}"
            sed -i 's/^prompt adam1/# prompt adam1/' "${FOLDER_DOT_ZSHRC}"
        fi
    fi
fi

# ===========================================================================
# Install user aliases
# ===========================================================================
# Check if user aliases setup is enabled
if [[ "${SETUP_USER_ALIASES_EN}" == "1" ]]; then
    # Check if user aliases file is already present
    if [ -f "${FILE_USER_ALIASES}" ]; then
        echo "[INF] User aliases file already exists. Skipping..."
    else
        echo ">>> Installing user aliases..."
        MakeThisDirExist "${FOLDER_FUS}"

        final_url="${URL_USER_ALIASES}"
        
        # Check network connection
        if ! PerformConnectionCheck "${final_url}"; then
            echo "[ERR] Failed to connect to ${final_url}. Skipping user aliases."
        # Check valid download file format
        elif ! PerformDownloadCheck "${final_url}"; then
            echo "[ERR] Invalid file format at ${final_url}. Skipping user aliases."
        else
            wget -q --show-progress -O "${FILE_USER_ALIASES}" "${final_url}"
            chmod +x "${FILE_USER_ALIASES}"

            AppendIfNotExist "${FOLDER_DOT_ZSHRC}" ""
            AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "# User aliases"
            AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "source ${FILE_USER_ALIASES}"

            echo ">>> User aliases installed successfully."
        fi
    fi
fi

# ===========================================================================
# Install JLink
# ===========================================================================
echo ">>> Processing JLink tools..."

InstallJLinkVersion "${SETUP_JLINK_V970_EN}" "${TAG_ARCHIVE_JLINK_V970}" "${FILE_ZIP_JLINK_V970}" "${FOLDER_JLINK_V970_DEST}"
InstallJLinkVersion "${SETUP_JLINK_V970_ARM_EN}" "${TAG_ARCHIVE_JLINK_V970}" "${FILE_ZIP_JLINK_V970_ARM}" "${FOLDER_JLINK_V970_ARM_DEST}"

InstallJLinkVersion "${SETUP_JLINK_V950_EN}" "${TAG_ARCHIVE_JLINK_V950}" "${FILE_ZIP_JLINK_V950}" "${FOLDER_JLINK_V950_DEST}"
InstallJLinkVersion "${SETUP_JLINK_V950_ARM_EN}" "${TAG_ARCHIVE_JLINK_V950}" "${FILE_ZIP_JLINK_V950_ARM}" "${FOLDER_JLINK_V950_ARM_DEST}"

# ===========================================================================
# Install Background image
# ===========================================================================
# Check if background image setup is enabled
if [[ "${SETUP_BACKGROUND_EN}" == "1" ]]; then
    BACKGROUND_DEST_IMG="IMG.$(date "+%H.%M.%S").${BACKGROUND_IMG_FILENAME}"
    FULL_BG_PATH="${FOLDER_BACKGROUND}/${BACKGROUND_DEST_IMG}"

    # Check if a background image with similar naming exists to avoid redundant download
    if ls "${FOLDER_BACKGROUND}/IMG."*".${BACKGROUND_IMG_FILENAME}" 1> /dev/null 2>&1; then
        echo "[INF] Background image already exists in ${FOLDER_BACKGROUND}. Skipping..."
    else
        echo ">>> Setting up desktop background..."
        MakeThisDirExist "${FOLDER_BACKGROUND}"
        cd "${FOLDER_DOWNLOADS}"

        final_url="${URL_BACKGROUND_IMG}"
        
        # Check network connection
        if ! PerformConnectionCheck "${final_url}"; then
            echo "[ERR] Failed to connect to ${final_url}. Skipping background image."
        # Check valid download file format
        elif ! PerformDownloadCheck "${final_url}"; then
            echo "[ERR] Invalid file format at ${final_url}. Skipping background image."
        else
            echo "[INF] Downloading background image..."
            wget -q --show-progress "${final_url}" -O "${BACKGROUND_DEST_IMG}"
            
            # Check if file was downloaded successfully
            if [ -f "${BACKGROUND_DEST_IMG}" ]; then
                sudo mkdir -p "/usr/share/backgrounds/xfce"
                sudo cp -v "${BACKGROUND_DEST_IMG}" "/usr/share/backgrounds/xfce/${BACKGROUND_DEST_IMG}"
                sudo chmod 644 "/usr/share/backgrounds/xfce/${BACKGROUND_DEST_IMG}"

                echo "[INF] Moving ${BACKGROUND_DEST_IMG} to ${FOLDER_BACKGROUND}"
                mv -f "${BACKGROUND_DEST_IMG}" "${FULL_BG_PATH}"
                echo "[INF] Background image installation successful."

                # Check if auto set background is enabled
                if [[ "${SETUP_AUTO_SET_BACKGROUND_EN}" == "1" ]]; then
                    echo "[INF] Set background for new image"
                    # Check if gsettings is available
                    if command -v gsettings >/dev/null 2>&1; then
                        echo "[INF] Applying background wallpaper setting..."
                        dbus-run-session gsettings set org.gnome.desktop.background picture-uri "file://${FULL_BG_PATH}" 2>/dev/null || true
                        dbus-run-session gsettings set org.gnome.desktop.background picture-uri-dark "file://${FULL_BG_PATH}" 2>/dev/null || true
                    fi
                fi
            else
                echo "[ERR] Failed to download background image from ${final_url}"
            fi
        fi
        cd "${FOLDER_CURRENT}"
    fi
fi

# ===========================================================================
# Install Clangd
# ===========================================================================
# Check if Clangd setup is enabled
if [[ "${SETUP_CLANGD_EN}" == "1" ]]; then
    # Check if Clangd is already installed
    if [ -x /usr/bin/clangd ] && [ -d "${FOLDER_CLANGD}" ]; then
        echo "[INF] Clangd is already installed. Skipping..."
    else
        echo ">>> Installing Clangd (${CLANGD_VERSION})..."
        cd "${FOLDER_DOWNLOADS}"

        final_url="${URL_CLANGD}"
        
        # Check network connection
        if ! PerformConnectionCheck "${final_url}"; then
            echo "[ERR] Failed to connect to ${final_url}. Skipping Clangd."
        # Check valid download file format
        elif ! PerformDownloadCheck "${final_url}"; then
            echo "[ERR] Invalid file format at ${final_url}. Skipping Clangd."
        else
            # Check if Clangd zip file is not downloaded yet
            if [ ! -f "${CLANGD_ZIP_FILENAME}" ]; then
                echo "[INF] Downloading Clangd zip file..."
                wget -q --show-progress "${final_url}" -O "${CLANGD_ZIP_FILENAME}"
            else
                echo "[INF] Clangd zip file already exists. Skipping download."
            fi

            # Check if archive exists for extraction
            if [ -f "${CLANGD_ZIP_FILENAME}" ]; then
                echo "[INF] Extracting ${CLANGD_ZIP_FILENAME}..."
                unzip -q -o "${CLANGD_ZIP_FILENAME}"

                # Check if extraction folder is valid
                if [ -d "${CLANGD_EXTRACTED_FILENAME}" ]; then
                    # Check for existing clangd folder and backup
                    if [ -d "${FOLDER_CLANGD}" ]; then
                        sudo mv "${FOLDER_CLANGD}" "${FOLDER_CLANGD}.bak.$(date +%s)"
                        echo "[INF] Backed up old clangd installation"
                    fi

                    echo "[INF] Moving ${CLANGD_EXTRACTED_FILENAME} to ${FOLDER_CLANGD}"
                    sudo mv "${CLANGD_EXTRACTED_FILENAME}" "${FOLDER_CLANGD}"

                    echo "[INF] Creating symlink /usr/bin/clangd -> ${FOLDER_CLANGD}/bin/clangd"
                    sudo ln -sf "${FOLDER_CLANGD}/bin/clangd" /usr/bin/clangd

                    rm -f "${CLANGD_ZIP_FILENAME}"
                    echo "[INF] Clangd installation successful."
                else
                    echo "[ERR] Extracted folder ${CLANGD_EXTRACTED_FILENAME} not found."
                fi
            else
                echo "[ERR] Failed to download Clangd from ${final_url}"
            fi
        fi
        cd "${FOLDER_CURRENT}"
    fi
fi

# ===========================================================================
# Install Nerd Fonts (Full Pack)
# ===========================================================================
# Check if Nerd Fonts setup is enabled
if [[ "${SETUP_NERD_FONTS_EN}" == "1" ]]; then
    # Check if Nerd Fonts are already installed in the user directory
    if ls "${FOLDER_HOME}/.local/share/fonts/NerdFonts/"* 1> /dev/null 2>&1; then
        echo "[INF] Nerd Fonts are already installed. Skipping..."
    else
        echo ">>> Installing Nerd Fonts full pack (~1.5GB, this may take a while)..."
        MakeThisDirExist "${FOLDER_DOWNLOADS}"
        cd "${FOLDER_DOWNLOADS}"

        # Check if font repository directory already exists
        if [ ! -d "${FOLDER_NERD_FONTS}" ]; then
            echo "[INF] Cloning Nerd Fonts repository (depth 1)..."
            git clone --depth 1 "${URL_NERD_FONTS_REPO}" "${FOLDER_NERD_FONTS}"
        else
            echo "[INF] Nerd Fonts repository already cloned. Skipping clone."
        fi

        # Check if install script is available
        if [ -f "${FOLDER_NERD_FONTS}/install.sh" ]; then
            echo "[INF] Running Nerd Fonts installation script..."
            cd "${FOLDER_NERD_FONTS}"
            ./install.sh

            echo "[INF] Cleaning up Nerd Fonts repository to save space..."
            cd "${FOLDER_CURRENT}"
            rm -rf "${FOLDER_NERD_FONTS}"
            
            echo "[INF] Nerd Fonts installation successful."
        else
            echo "[ERR] Nerd Fonts install.sh not found."
        fi
        
        cd "${FOLDER_CURRENT}"
    fi
fi

# Check if HCMC timezone setup is enabled
if [[ "${SETUP_HCMC_TIME_EN}" == "1" ]]; then
    # Check if timezone is already linked properly
    if [ "$(readlink -f /etc/localtime)" != "/usr/share/zoneinfo/Asia/Ho_Chi_Minh" ]; then
        echo ">>> Installing HCMC time zone ..."
        sudo ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime
    fi
fi

# ===========================================================================
# Goodbye
# ===========================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════╗"
echo "║                            Setup complete!                                       ║"
echo "║                      Run: source ~/.zshrc                                        ║"
echo "║                      Or restart your shell to apply changes                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════╝"