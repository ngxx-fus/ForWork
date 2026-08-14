#!/usr/bin/env bash
###############################################################################
# Setup script for Coder workspace (Ubuntu-based)
# - Install Neovim + custom config
# - Install Oh-My-Zsh + plugins + custom theme
# - Install user aliases
# - Install SEGGER J-Link tools
# - Setup desktop background wallpaper
#
# Usage: bash setup.sh
###############################################################################

set -e  # Exit immediately on error
set -u  # Treat unset variables as error

# ===========================================================================
# Global config flags (set to 1 to enable, 0 to skip)
# ===========================================================================
export SETUP_OHMYZSH_EN=1
export SETUP_NVIM_EN=0
export SETUP_ADD_APT_REPO_EN=1
export SETUP_USER_ALIASES_EN=1
export SETUP_JLINK_EN=1
export SETUP_BACKGROUND_EN=1

# ===========================================================================
# Versioning & Security
# ===========================================================================
export NVIM_VERSION="nightly"
export NVIM_TARBALL="nvim-linux-x86_64.tar.gz"
export NIVM_INSTALL_DIRNAME="nvim-linux-x86_64"
export JLINK_VERSION_NAME="JLink-V9.5.0/x64-Linux"
export JLINK_TARBALL_NAME="JLink_Linux_V950_x86_64.tgz"
export JLINK_INSTALL_DIRNAME="JLink_V950"
export BACKGROUND_IMG_FILENAME="IMG_4273.JPG"

# ===========================================================================
# Global private vars
# ===========================================================================
export PATH_FOLDER_CURRENT=$(pwd)
export PATH_FOLDER_HOME="/home/coder"
export PATH_FOLDER_DOT_ZSHRC="${PATH_FOLDER_HOME}/.zshrc"
export PATH_FOLDER_DOT_OH_MY_ZSH="${PATH_FOLDER_HOME}/.oh-my-zsh"
export PATH_FOLDER_NVIM_CONFIG="${PATH_FOLDER_HOME}/.config/nvim"
export PATH_FOLDER_DOWNLOADS="${PATH_FOLDER_HOME}/Downloads"
export PATH_FOLDER_FUS="${PATH_FOLDER_HOME}/.fus"
export PATH_FOLDER_JLINK="${PATH_FOLDER_HOME}/workspace/${JLINK_INSTALL_DIRNAME}"
export PATH_FOLDER_BACKGROUND="${PATH_FOLDER_FUS}/.BG"
export PATH_FILE_USER_ALIASES="${PATH_FOLDER_FUS}/user_aliases.sh"

# Theme
export PATH_FOLDER_OMZ_THEMES="${PATH_FOLDER_DOT_OH_MY_ZSH}/themes"
export PATH_FILE_NGXXFUS_THEME="${PATH_FOLDER_OMZ_THEMES}/ngxxfus.zsh-theme"

# URLs
export URL_FORWORK_ROOTDIR="https://raw.githubusercontent.com/ngxx-fus/ForWork/refs/heads/main"
export URL_USER_ALIASES="${URL_FORWORK_ROOTDIR}/.assert/useralias.sh"
export URL_NGXXFUS_THEME="${URL_FORWORK_ROOTDIR}/.assert/ngxxfus.zsh-theme"
export URL_JLINK_ARCHIVE="${URL_FORWORK_ROOTDIR}/.assert/${JLINK_VERSION_NAME}/${JLINK_TARBALL_NAME}"
export URL_BACKGROUND_IMG="${URL_FORWORK_ROOTDIR}/.imgs/BG/IMG_4273.JPG"
export URL_NVIM_DOWNLOAD="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TARBALL}"
export URL_NEOVIM_CONF_REPO="https://github.com/ngxx-fus/neovim-conf.git"
export URL_OHMYZSH_INSTALL_SCRIPT="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
export URL_ZSH_SYNTAX_HIGHLIGHTING_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
export URL_ZSH_AUTOSUGGESTIONS_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
export URL_ZSH_Z_REPO="https://github.com/agkozak/zsh-z.git"

# ===========================================================================
# Helper functions
# ===========================================================================

# ---------------------------------------------------------------------------
# MakeThisDirExist <path>
# Ensure the given directory exists, creating it (with parents) if needed.
# Args:
#   $1 : Path to the directory to create.
# Returns:
#   0  : Directory exists or was created successfully.
#   1  : Wrong number of arguments or failed to create directory.
# ---------------------------------------------------------------------------
MakeThisDirExist() {
    if [[ $# -ne 1 ]]; then
        echo "[ERR][MakeThisDirExist] Wrong number of args (expected 1, got $#)"
        return 1
    fi

    local target_dir="$1"

    if [ -d "${target_dir}" ]; then
        return 0
    fi

    if mkdir -p "${target_dir}"; then
        echo "[INF][MakeThisDirExist] Created: '${target_dir}'"
        return 0
    else
        echo "[ERR][MakeThisDirExist] Failed to create: '${target_dir}'"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# AppendIfNotExist <file> <line>
# Append a line to a file only if it does not already exist in the file.
# Args:
#   $1 : Target file path.
#   $2 : Line to append.
# ---------------------------------------------------------------------------
AppendIfNotExist() {
    if [[ $# -ne 2 ]]; then
        echo "[ERR][AppendIfNotExist] Wrong number of args (expected 2, got $#)"
        return 1
    fi

    local target_file="$1"
    local line="$2"

    if ! grep -qF "${line}" "${target_file}" 2>/dev/null; then
        echo "${line}" >> "${target_file}"
        echo "[INF][AppendIfNotExist] Appended to ${target_file}: ${line}"
    else
        echo "[INF][AppendIfNotExist] Already exists, skipping: ${line}"
    fi
}

# ===========================================================================
# Pre-flight Checks
# ===========================================================================
echo ">>> Running pre-flight checks..."
if ! sudo -n true 2>/dev/null; then
    echo "[ERR] Sudo requires a password. Please run in an environment with passwordless sudo or authenticate first."
    exit 1
fi

# ===========================================================================
# Pre-create required directories
# ===========================================================================
MakeThisDirExist "${PATH_FOLDER_CURRENT}"
MakeThisDirExist "$(dirname "${PATH_FOLDER_DOT_ZSHRC}")"
MakeThisDirExist "${PATH_FOLDER_DOWNLOADS}"
MakeThisDirExist "${PATH_FOLDER_FUS}"

# ===========================================================================
# Add repository (optional)
# ===========================================================================
if [[ "${SETUP_ADD_APT_REPO_EN}" == "1" ]]; then
    echo ">>> Updating apt repositories..."
    export DEBIAN_FRONTEND=noninteractive
    sudo add-apt-repository universe -y
    sudo apt update -y
    # Removed apt upgrade -y to prevent breaking dependencies uncontrollably
fi

# ===========================================================================
# Install Neovim
# ===========================================================================
if [[ "${SETUP_NVIM_EN}" == "1" ]]; then
    echo ">>> Installing Neovim (${NVIM_VERSION})..."
    
    # --- Install prerequisites ---
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y git gcc make ripgrep fd-find nodejs npm python3 python3-pip unzip curl

    # --- Download ---
    cd "${PATH_FOLDER_DOWNLOADS}"
    wget -q --show-progress "${URL_NVIM_DOWNLOAD}"

    # --- Extract ---
    tar -zxvf "${NVIM_TARBALL}"

    # --- Install to /opt/nvim (with backup) ---
    if [ -d /opt/nvim ]; then
        sudo cp -vrf /opt/nvim "/opt/nvim.bak.$(date +%s)"
        sudo rm -vrf /opt/nvim
        echo "[INF] Backed up old /opt/nvim ---> /opt/nvim.bak.$(date +%s)"
    fi
    if [ -d /usr/local/bin/nvim ]; then
        sudo rm -vf /usr/local/bin/nvim 
        echo "[INF] Removed sym-link /usr/local/bin/nvim"
    fi

    sudo mkdir -p /opt/nvim
    sudo cp -vrf "${NIVM_INSTALL_DIRNAME}/." /opt/nvim

    # --- Clone custom Neovim config (with backup) ---
    if [ -d "${PATH_FOLDER_NVIM_CONFIG}" ]; then
        mv "${PATH_FOLDER_NVIM_CONFIG}" "${PATH_FOLDER_NVIM_CONFIG}.bak.$(date +%s)"
        echo "[INF] Backed up old Neovim config"
    fi
    MakeThisDirExist "${PATH_FOLDER_NVIM_CONFIG}"

    git clone --recurse-submodules \
        "${URL_NEOVIM_CONF_REPO}" \
        "${PATH_FOLDER_NVIM_CONFIG}"

    # --- Return to original directory ---
    cd "${PATH_FOLDER_CURRENT}"

    echo ">>> Neovim installed successfully."
fi

# ===========================================================================
# Install Oh-My-Zsh + plugins + custom theme
# ===========================================================================
if [[ "${SETUP_OHMYZSH_EN}" == "1" ]]; then
    echo ">>> Installing Oh-My-Zsh..."

    # --- Backup existing .oh-my-zsh ---
    if [ -d "${PATH_FOLDER_DOT_OH_MY_ZSH}" ]; then
        mv "${PATH_FOLDER_DOT_OH_MY_ZSH}" "${PATH_FOLDER_DOT_OH_MY_ZSH}.bak.$(date +%s)"
        echo "[INF] Backed up old .oh-my-zsh"
    fi

    # --- Backup existing .zshrc ---
    if [ -f "${PATH_FOLDER_DOT_ZSHRC}" ]; then
        cp -vf "${PATH_FOLDER_DOT_ZSHRC}" "${PATH_FOLDER_DOT_ZSHRC}.bak"
        echo ">>> Backed up .zshrc → .zshrc.bak"
    fi

    # --- Install Oh-My-Zsh safely ---
    OMZ_INSTALLER="${PATH_FOLDER_DOWNLOADS}/omz_install.sh"
    curl -fsSL "${URL_OHMYZSH_INSTALL_SCRIPT}" -o "${OMZ_INSTALLER}"
    sh "${OMZ_INSTALLER}" "" --unattended

    # --- Install plugins (Idempotent) ---
    export ZSH_CUSTOM="${PATH_FOLDER_DOT_OH_MY_ZSH}/custom"

    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
        git clone "${URL_ZSH_SYNTAX_HIGHLIGHTING_REPO}" "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
    fi

    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
        git clone "${URL_ZSH_AUTOSUGGESTIONS_REPO}" "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
    fi

    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-z" ]; then
        git clone "${URL_ZSH_Z_REPO}" "${ZSH_CUSTOM}/plugins/zsh-z"
    fi

    # --- Enable plugins in .zshrc ---
    sed -i \
        's/^plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-z)/' \
        "${PATH_FOLDER_DOT_ZSHRC}"

    # --- Download custom theme ---
    echo ">>> Installing ngxxfus theme..."
    MakeThisDirExist "${PATH_FOLDER_OMZ_THEMES}"

    wget -q --show-progress \
        -O "${PATH_FILE_NGXXFUS_THEME}" \
        "${URL_NGXXFUS_THEME}"

    # --- Set theme in .zshrc ---
    if grep -q '^ZSH_THEME=' "${PATH_FOLDER_DOT_ZSHRC}"; then
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME="ngxxfus"/' "${PATH_FOLDER_DOT_ZSHRC}"
    else
        AppendIfNotExist "${PATH_FOLDER_DOT_ZSHRC}" 'ZSH_THEME="ngxxfus"'
    fi

    # --- Restore custom parts of old .zshrc safely using absolute path ---
    if [ -f "${PATH_FOLDER_DOT_ZSHRC}.bak" ]; then
        printf "\n\n\n#### ORIGINAL .ZSHRC ####\n\n\n" >> "${PATH_FOLDER_DOT_ZSHRC}"
        cat "${PATH_FOLDER_DOT_ZSHRC}.bak" >> "${PATH_FOLDER_DOT_ZSHRC}"
    fi

    # --- Comment out specific prompt configs using absolute path ---
    sed -i 's/^autoload -Uz promptinit/# autoload -Uz promptinit/' "${PATH_FOLDER_DOT_ZSHRC}"
    sed -i 's/^promptinit/# promptinit/' "${PATH_FOLDER_DOT_ZSHRC}"
    sed -i 's/^prompt adam1/# prompt adam1/' "${PATH_FOLDER_DOT_ZSHRC}"
fi

# ===========================================================================
# Install user aliases
# ===========================================================================
if [[ "${SETUP_USER_ALIASES_EN}" == "1" ]]; then
    echo ">>> Installing user aliases..."

    MakeThisDirExist "${PATH_FOLDER_FUS}"

    wget -q --show-progress \
        -O "${PATH_FILE_USER_ALIASES}" \
        "${URL_USER_ALIASES}"

    chmod +x "${PATH_FILE_USER_ALIASES}"

    # --- Append source line to .zshrc ---
    AppendIfNotExist "${PATH_FOLDER_DOT_ZSHRC}" ""
    AppendIfNotExist "${PATH_FOLDER_DOT_ZSHRC}" "# User aliases"
    AppendIfNotExist "${PATH_FOLDER_DOT_ZSHRC}" "source ${PATH_FILE_USER_ALIASES}"

    echo ">>> User aliases installed successfully."
fi

# ===========================================================================
# Install JLink
# ===========================================================================
if [[ "${SETUP_JLINK_EN}" == "1" ]]; then
    echo ">>> Installing JLink software package..."

    # Ensure clean target directory
    if [ -d "${PATH_FOLDER_JLINK}" ]; then
        sudo rm -rf "${PATH_FOLDER_JLINK}"
        echo "[INF] Removed existing directory: ${PATH_FOLDER_JLINK}"
    fi
    MakeThisDirExist "${PATH_FOLDER_JLINK}"

    # Switch execution path to Downloads directory
    cd "${PATH_FOLDER_DOWNLOADS}"

    echo "[INF] Downloading JLink tarball..."
    wget -q --show-progress "${URL_JLINK_ARCHIVE}" -O "${JLINK_TARBALL_NAME}"

    if [ -f "${JLINK_TARBALL_NAME}" ]; then
        echo "[INF] Extracting ${JLINK_TARBALL_NAME}..."
        tar -zxvf "${JLINK_TARBALL_NAME}"

        if [ -d "${JLINK_INSTALL_DIRNAME}" ]; then
            echo "[INF] Copying ${JLINK_INSTALL_DIRNAME} to ${PATH_FOLDER_JLINK}"
            cp -vrf "./${JLINK_INSTALL_DIRNAME}/." "${PATH_FOLDER_JLINK}"
            
            # Cleanup downloaded tarball and extracted temporary folder
            rm -rf "${JLINK_TARBALL_NAME}" "./${JLINK_INSTALL_DIRNAME}"
            echo "[INF] JLink installation successful."
        else
            echo "[ERR] Extracted folder ${JLINK_INSTALL_DIRNAME} not found."
        fi
    else
        echo "[ERR] Failed to download JLink from ${URL_JLINK_ARCHIVE}"
    fi

    # Return execution context back to starting directory
    cd "${PATH_FOLDER_CURRENT}"
fi

# ===========================================================================
# Install Background image
# ===========================================================================
if [[ "${SETUP_BACKGROUND_EN}" == "1" ]]; then
    echo ">>> Setting up desktop background..."

    MakeThisDirExist "${PATH_FOLDER_BACKGROUND}"

    # Switch execution path to Downloads directory
    cd "${PATH_FOLDER_DOWNLOADS}"

    BACKGROUND_DEST_IMG="IMG.$(date "+%H.%M.%S").${BACKGROUND_IMG_FILENAME}"
    
    echo "[INF] Downloading background image..."
    wget -q --show-progress "${URL_BACKGROUND_IMG}" -O "${BACKGROUND_DEST_IMG}"
    
    if [ -f "${BACKGROUND_DEST_IMG}" ]; then
        echo "[INF] Moving ${BACKGROUND_DEST_IMG} to ${PATH_FOLDER_BACKGROUND}"
        mv -f "${BACKGROUND_DEST_IMG}" "${PATH_FOLDER_BACKGROUND}/${BACKGROUND_DEST_IMG}"
        echo "[INF] Background image installation successful."
    else
        echo "[ERR] Failed to download background image from ${URL_BACKGROUND_IMG}"
    fi

    # Return execution context back to starting directory
    cd "${PATH_FOLDER_CURRENT}"
fi

# ===========================================================================
# Goodbye
# ===========================================================================
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Setup complete!                 ║"
echo "║  Run: source ~/.zshrc                    ║"
echo "║  Or restart your shell to apply changes  ║"
echo "╚══════════════════════════════════════════╝"