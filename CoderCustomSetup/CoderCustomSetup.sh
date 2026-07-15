#!/usr/bin/env bash
###############################################################################
# Setup script for Coder workspace (Ubuntu-based)
# - Install Neovim + custom config
# - Install Oh-My-Zsh + plugins + custom theme
# - Install user aliases
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

# ===========================================================================
# Versioning & Security
# ===========================================================================
export NVIM_VERSION="v0.10.0"
export NVIM_TARBALL="nvim-linux64.tar.gz"

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
export PATH_FILE_USER_ALIASES="${PATH_FOLDER_FUS}/user_aliases.sh"

# Theme
export PATH_FOLDER_OMZ_THEMES="${PATH_FOLDER_DOT_OH_MY_ZSH}/themes"
export PATH_FILE_NGXXFUS_THEME="${PATH_FOLDER_OMZ_THEMES}/ngxxfus.zsh-theme"

# URLs
export URL_USER_ALIASES="https://raw.githubusercontent.com/ngxx-fus/ForWork/refs/heads/main/.assert/useralias.sh"
export URL_NGXXFUS_THEME="https://raw.githubusercontent.com/ngxx-fus/ForWork/refs/heads/main/.assert/ngxxfus.zsh-theme"
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
        sudo mv /opt/nvim "/opt/nvim.bak.$(date +%s)"
        echo "[INF] Backed up old /opt/nvim"
    fi
    sudo mkdir -p /opt/nvim
    sudo cp -vrf nvim-linux64/. /opt/nvim

    # --- Add nvim to PATH in .zshrc ---
    AppendIfNotExist "${PATH_FOLDER_DOT_ZSHRC}" 'export PATH="$PATH:/opt/nvim/bin"'

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
    # NOTE: Add SHA256 checksum verification here if required for strict compliance
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
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Setup complete!                 ║"
echo "║  Run: source ~/.zshrc                    ║"
echo "║  Or restart your shell to apply changes  ║"
echo "╚══════════════════════════════════════════╝"