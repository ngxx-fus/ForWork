#!/usr/bin/env bash
###############################################################################
# Setup script for Coder workspace (Ubuntu-based)
# - Install Neovim + custom config
# - Install Oh-My-Zsh + plugins + custom theme
# - Install user aliases
# - Install SEGGER J-Link tools
# - Setup desktop background wallpaper
# - Install Clangd
# - Install custom APT packages
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
export SETUP_NVIM_PREREQUISITES_EN=1        # only works if SETUP_NVIM_EN=1
export SETUP_ADD_APT_REPO_EN=1
export SETUP_USER_ALIASES_EN=1
export SETUP_BACKGROUND_EN=1
export SETUP_AUTO_SET_BACKGROUND_EN=0       # only works if SETUP_BACKGROUND_EN=1
export SETUP_CLANGD=1
export SETUP_JLINK_V950_EN=1
export SETUP_JLINK_V950_ARM_EN=1
export SETUP_JLINK_V970_EN=1
export SETUP_JLINK_V970_ARM_EN=1

export SETUP_CONN_CHECK_EN=1
export SETUP_VALID_FILE_CHECK_FILE_EN=0     # temporarily not implemented/active

export SETUP_APT_INSTALL_LIST_EN=1
export SETUP_APT_INSTALL_LIST=(
    "btop"
    "tree"
    "duf"
)

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

# ===========================================================================
# Helper functions
# ===========================================================================

/*
 * @brief Ensure the given directory exists, creating it (with parents) if needed.
 * @param target_dir Path to the directory to create.
 */
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

/*
 * @brief Append a line to a file only if it does not already exist in the file.
 * @param target_file Target file path.
 * @param line Line to append.
 */
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

/*
 * @brief Extract base filename located after the last slash and before the last dot.
 * @param path Input path string.
 */
GetBaseName() {
    path="$1"

    if [ -z "$path" ] || [ "${path%[/\\]}" != "$path" ]; then
        return 1
    fi

    filename="${path##*[/\\]}"

    if [ "$filename" = "${filename%.*}" ]; then
        return 1
    fi

    basename="${filename%.*}"
    printf '%s\n' "$basename"

    return 0
}

/*
 * @brief Check if the provided URL is reachable.
 * @param target_url The URL to check.
 * @return 0 if reachable, 1 otherwise.
 */
PerformConnectionCheck() {
    if [[ $# -ne 1 ]]; then
        echo "[ERR][PerformConnectionCheck] Missing URL argument."
        return 1
    fi

    local target_url="$1"

    if [[ "${SETUP_CONN_CHECK_EN}" != "1" ]]; then
        return 0
    fi

    echo "[INF][PerformConnectionCheck] Testing connection to: ${target_url}"
    # Use curl to fetch headers only, silently, follow redirects, fail on errors
    if curl --output /dev/null --silent --head --fail --location "${target_url}"; then
        echo "[INF][PerformConnectionCheck] Connection OK."
        return 0
    else
        return 1
    fi
}

/*
 * @brief Check if the provided URL downloads an actual file rather than an HTML page.
 * @param target_url The URL to check.
 * @return 0 if valid file, 1 if HTML page.
 */
PerformDownloadCheck() {
    if [[ $# -ne 1 ]]; then
        echo "[ERR][PerformDownloadCheck] Missing URL argument."
        return 1
    fi

    local target_url="$1"

    if [[ "${SETUP_VALID_FILE_CHECK_FILE_EN}" != "1" ]]; then
        return 0
    fi

    echo "[INF][PerformDownloadCheck] Validating file type for: ${target_url}"
    local content_type
    
    # Fetch headers and grep for Content-Type
    content_type=$(curl -sI -L "${target_url}" | grep -i -E "^Content-Type:" | tail -n 1)

    if echo "${content_type}" | grep -q -i "text/html"; then
        echo "[ERR][PerformDownloadCheck] URL returned HTML instead of a valid file!"
        return 1
    else
        echo "[INF][PerformDownloadCheck] File format OK."
        return 0
    fi
}

/*
 * @brief Download, extract, and install a specific JLink version.
 * @param enable_flag   Installation enable flag (1 to run, 0 to skip).
 * @param tag_name      GitHub release tag.
 * @param file_name     Archive file name (e.g., .tgz).
 * @param dest_name     Destination folder name inside workspace.
 */
InstallJLinkVersion() {
    local enable_flag="$1"
    local tag_name="$2"
    local file_name="$3"
    local dest_name="$4"

    if [[ "${enable_flag}" != "1" ]]; then
        return 0
    fi

    echo ">>> Installing ${dest_name}..."

    local dest_path="${FOLDER_JLINK_COMM_DEST}/${dest_name}"
    local final_url="${URL_JLINK_ARCHIVES}/${tag_name}/${file_name}"
    
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping ${dest_name}."
        return 1
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping ${dest_name}."
        return 1
    else
        local extracted_folder="${file_name%.*}"

        if [ -d "${dest_path}" ]; then
            rm -rf "${dest_path}"
            echo "[INF] Removed existing directory: ${dest_path}"
        fi

        MakeThisDirExist "${FOLDER_JLINK_COMM_DEST}"
        cd "${FOLDER_DOWNLOADS}"

        echo "[INF] Downloading ${file_name}..."
        wget -q --show-progress "${final_url}" -O "${file_name}"

        if [ -f "${file_name}" ]; then
            echo "[INF] Extracting ${file_name}..."
            tar -zxvf "${file_name}"

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

    return 0
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
MakeThisDirExist "${FOLDER_CURRENT}"
MakeThisDirExist "$(dirname "${FOLDER_DOT_ZSHRC}")"
MakeThisDirExist "${FOLDER_DOWNLOADS}"
MakeThisDirExist "${FOLDER_FUS}"

# ===========================================================================
# Add repository & Install APT Packages
# ===========================================================================
if [[ "${SETUP_ADD_APT_REPO_EN}" == "1" ]]; then
    echo ">>> Updating apt repositories..."
    export DEBIAN_FRONTEND=noninteractive
    sudo add-apt-repository universe -y
    sudo apt update -y
fi

if [[ "${SETUP_APT_INSTALL_LIST_EN}" == "1" ]]; then
    echo ">>> Installing custom APT packages..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y "${SETUP_APT_INSTALL_LIST[@]}"
fi

# ===========================================================================
# Install Neovim
# ===========================================================================
if [[ "${SETUP_NVIM_EN}" == "1" ]]; then
    echo ">>> Installing Neovim (${NVIM_VERSION})..."
    
    local final_url="${URL_NVIM_DOWNLOAD}"
    
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping Neovim."
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping Neovim."
    else
        # --- Install prerequisites ---
        if [[ "${SETUP_NVIM_PREREQUISITES_EN}" == "1" ]]; then 
            echo "[INF] Installing Neovim prerequisites..."
            export DEBIAN_FRONTEND=noninteractive
            sudo apt update && sudo apt install -y \
                git \
                build-essential \
                gcc \
                g++ \
                make \
                ripgrep \
                fd-find \
                unzip \
                curl \
                tar \
                nodejs \
                npm \
                python3 \
                python3-pip \
                xclip \
                wl-clipboard

            # --- Create symlink for fd-find if missing ---
            MakeThisDirExist "${FOLDER_HOME}/.local/bin"
            if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
                ln -sf "$(which fdfind)" "${FOLDER_HOME}/.local/bin/fd"
                echo "[INF] Created symlink for fd -> fdfind in ~/.local/bin"
            fi
        fi

        # --- Download ---
        cd "${FOLDER_DOWNLOADS}"
        echo "[INF] Downloading Neovim tarball..."
        wget -q --show-progress "${final_url}" -O "${NVIM_TARBALL}"

        # --- Extract ---
        echo "[INF] Extracting ${NVIM_TARBALL}..."
        tar -zxvf "${NVIM_TARBALL}"

        # --- Install to /opt/nvim (with backup) ---
        if [ -d /opt/nvim ]; then
            sudo cp -vrf /opt/nvim "/opt/nvim.bak.$(date +%s)"
            sudo rm -rf /opt/nvim
            echo "[INF] Backed up old /opt/nvim ---> /opt/nvim.bak.$(date +%s)"
        fi
        if [ -e /usr/local/bin/nvim ]; then
            sudo rm -vf /usr/local/bin/nvim 
            echo "[INF] Removed existing /usr/local/bin/nvim"
        fi

        sudo mkdir -p /opt/nvim
        sudo cp -vrf "${NIVM_INSTALL_DIRNAME}/." /opt/nvim

        # Create symlink in /usr/local/bin for global nvim access
        sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
        echo "[INF] Created symlink /usr/local/bin/nvim -> /opt/nvim/bin/nvim"

        # --- Clone custom Neovim config (with backup) ---
        if [ -d "${FOLDER_NVIM_CONFIG}" ]; then
            mv "${FOLDER_NVIM_CONFIG}" "${FOLDER_NVIM_CONFIG}.bak.$(date +%s)"
            echo "[INF] Backed up old Neovim config"
        fi
        MakeThisDirExist "${FOLDER_NVIM_CONFIG}"

        echo "[INF] Cloning Neovim configuration repository..."
        git clone --recurse-submodules \
            "${URL_NEOVIM_CONF_REPO}" \
            "${FOLDER_NVIM_CONFIG}"

        # --- Cleanup downloaded archive ---
        rm -rf "${NVIM_TARBALL}" "./${NIVM_INSTALL_DIRNAME}"

        # --- Return to original directory ---
        cd "${FOLDER_CURRENT}"

        echo ">>> Neovim installed successfully."
    fi
fi

# ===========================================================================
# Install Oh-My-Zsh + plugins + custom theme
# ===========================================================================
if [[ "${SETUP_OHMYZSH_EN}" == "1" ]]; then
    echo ">>> Installing Oh-My-Zsh..."

    # --- Backup existing .oh-my-zsh ---
    if [ -d "${FOLDER_DOT_OH_MY_ZSH}" ]; then
        mv "${FOLDER_DOT_OH_MY_ZSH}" "${FOLDER_DOT_OH_MY_ZSH}.bak.$(date +%s)"
        echo "[INF] Backed up old .oh-my-zsh"
    fi

    # --- Backup existing .zshrc ---
    if [ -f "${FOLDER_DOT_ZSHRC}" ]; then
        cp -vf "${FOLDER_DOT_ZSHRC}" "${FOLDER_DOT_ZSHRC}.bak"
        echo ">>> Backed up .zshrc → .zshrc.bak"
    fi

    # --- Install Oh-My-Zsh safely ---
    local final_url="${URL_OHMYZSH_INSTALL_SCRIPT}"
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping Oh-My-Zsh installer."
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping Oh-My-Zsh installer."
    else
        OMZ_INSTALLER="${FOLDER_DOWNLOADS}/omz_install.sh"
        curl -fsSL "${final_url}" -o "${OMZ_INSTALLER}"
        sh "${OMZ_INSTALLER}" "" --unattended

        # --- Install plugins (Idempotent) ---
        export ZSH_CUSTOM="${FOLDER_DOT_OH_MY_ZSH}/custom"

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
            "${FOLDER_DOT_ZSHRC}"

        # --- Download custom theme ---
        echo ">>> Installing ngxxfus theme..."
        MakeThisDirExist "${FOLDER_OMZ_THEMES}"

        local theme_url="${URL_NGXXFUS_THEME}"
        if ! PerformConnectionCheck "${theme_url}"; then
            echo "[ERR] Failed to connect to ${theme_url}. Skipping theme setup."
        elif ! PerformDownloadCheck "${theme_url}"; then
            echo "[ERR] Invalid file format at ${theme_url}. Skipping theme setup."
        else
            wget -q --show-progress -O "${FILE_NGXXFUS_THEME}" "${theme_url}"

            # --- Set theme in .zshrc ---
            if grep -q '^ZSH_THEME=' "${FOLDER_DOT_ZSHRC}"; then
                sed -i 's/^ZSH_THEME=.*/ZSH_THEME="ngxxfus"/' "${FOLDER_DOT_ZSHRC}"
            else
                AppendIfNotExist "${FOLDER_DOT_ZSHRC}" 'ZSH_THEME="ngxxfus"'
            fi
        fi

        # --- Restore custom parts of old .zshrc safely using absolute path ---
        if [ -f "${FOLDER_DOT_ZSHRC}.bak" ]; then
            printf "\n\n\n#### ORIGINAL .ZSHRC ####\n\n\n" >> "${FOLDER_DOT_ZSHRC}"
            cat "${FOLDER_DOT_ZSHRC}.bak" >> "${FOLDER_DOT_ZSHRC}"
        fi

        # --- Comment out specific prompt configs using absolute path ---
        sed -i 's/^autoload -Uz promptinit/# autoload -Uz promptinit/' "${FOLDER_DOT_ZSHRC}"
        sed -i 's/^promptinit/# promptinit/' "${FOLDER_DOT_ZSHRC}"
        sed -i 's/^prompt adam1/# prompt adam1/' "${FOLDER_DOT_ZSHRC}"
    fi
fi

# ===========================================================================
# Install user aliases
# ===========================================================================
if [[ "${SETUP_USER_ALIASES_EN}" == "1" ]]; then
    echo ">>> Installing user aliases..."

    MakeThisDirExist "${FOLDER_FUS}"

    local final_url="${URL_USER_ALIASES}"
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping user aliases."
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping user aliases."
    else
        wget -q --show-progress -O "${FILE_USER_ALIASES}" "${final_url}"
        chmod +x "${FILE_USER_ALIASES}"

        # --- Append source line to .zshrc ---
        AppendIfNotExist "${FOLDER_DOT_ZSHRC}" ""
        AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "# User aliases"
        AppendIfNotExist "${FOLDER_DOT_ZSHRC}" "source ${FILE_USER_ALIASES}"

        echo ">>> User aliases installed successfully."
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
if [[ "${SETUP_BACKGROUND_EN}" == "1" ]]; then
    echo ">>> Setting up desktop background..."

    MakeThisDirExist "${FOLDER_BACKGROUND}"
    cd "${FOLDER_DOWNLOADS}"

    local final_url="${URL_BACKGROUND_IMG}"
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping background image."
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping background image."
    else
        BACKGROUND_DEST_IMG="IMG.$(date "+%H.%M.%S").${BACKGROUND_IMG_FILENAME}"
        FULL_BG_PATH="${FOLDER_BACKGROUND}/${BACKGROUND_DEST_IMG}"
        
        echo "[INF] Downloading background image..."
        wget -q --show-progress "${final_url}" -O "${BACKGROUND_DEST_IMG}"
        
        if [ -f "${BACKGROUND_DEST_IMG}" ]; then
            # Ensure system background directory exists before copying
            sudo mkdir -p "/usr/share/backgrounds/xfce"
            sudo cp -v "${BACKGROUND_DEST_IMG}" "/usr/share/backgrounds/xfce/${BACKGROUND_DEST_IMG}"
            sudo chmod 644 "/usr/share/backgrounds/xfce/${BACKGROUND_DEST_IMG}"

            # Move original file to user background folder
            echo "[INF] Moving ${BACKGROUND_DEST_IMG} to ${FOLDER_BACKGROUND}"
            mv -f "${BACKGROUND_DEST_IMG}" "${FULL_BG_PATH}"
            echo "[INF] Background image installation successful."

            if [[ "${SETUP_AUTO_SET_BACKGROUND_EN}" == "1" ]]; then
                echo "[INF] Set background for new image"
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

    # Return execution context back to starting directory
    cd "${FOLDER_CURRENT}"
fi

# ===========================================================================
# Install Clangd
# ===========================================================================
if [[ "${SETUP_CLANGD}" == "1" ]]; then
    echo ">>> Installing Clangd (${CLANGD_VERSION})..."

    cd "${FOLDER_DOWNLOADS}"

    local final_url="${URL_CLANGD}"
    if ! PerformConnectionCheck "${final_url}"; then
        echo "[ERR] Failed to connect to ${final_url}. Skipping Clangd."
    elif ! PerformDownloadCheck "${final_url}"; then
        echo "[ERR] Invalid file format at ${final_url}. Skipping Clangd."
    else
        echo "[INF] Downloading Clangd zip file..."
        wget -q --show-progress "${final_url}" -O "${CLANGD_ZIP_FILENAME}"

        if [ -f "${CLANGD_ZIP_FILENAME}" ]; then
            echo "[INF] Extracting ${CLANGD_ZIP_FILENAME}..."
            unzip -q "${CLANGD_ZIP_FILENAME}"

            if [ -d "${CLANGD_EXTRACTED_FILENAME}" ]; then
                # Backup existing installation if it exists
                if [ -d "${FOLDER_CLANGD}" ]; then
                    sudo mv "${FOLDER_CLANGD}" "${FOLDER_CLANGD}.bak.$(date +%s)"
                    echo "[INF] Backed up old clangd installation"
                fi

                # Move extracted folder to /opt
                echo "[INF] Moving ${CLANGD_EXTRACTED_FILENAME} to ${FOLDER_CLANGD}"
                sudo mv "${CLANGD_EXTRACTED_FILENAME}" "${FOLDER_CLANGD}"

                # Create symlink for global access
                echo "[INF] Creating symlink /usr/local/bin/clangd -> ${FOLDER_CLANGD}/bin/clangd"
                sudo ln -sf "${FOLDER_CLANGD}/bin/clangd" /usr/bin/clangd

                # Cleanup downloaded zip
                rm -f "${CLANGD_ZIP_FILENAME}"
                echo "[INF] Clangd installation successful."
            else
                echo "[ERR] Extracted folder ${CLANGD_EXTRACTED_FILENAME} not found."
            fi
        else
            echo "[ERR] Failed to download Clangd from ${final_url}"
        fi
    fi

    # Return execution context back to starting directory
    cd "${FOLDER_CURRENT}"
fi

# ===========================================================================
# Goodbye
# ===========================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════╗"
echo "║                              Setup complete!                                     ║"
echo "║                      Run: source ~/.zshrc                                        ║"
echo "║                      Or restart your shell to apply changes                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════╝"
