alias ll="ls -lath"
alias la="ls -at"
alias l="ls -CF"

# APT Package Manager (Ubuntu)
alias s="sudo apt update"
alias i="sudo apt install -y"
alias u="sudo apt update && sudo apt upgrade -y"
alias r="sudo apt remove -y"
alias q="apt search"

# Navigation
alias downloads="cd ~/Downloads"
alias desktop="cd ~/Desktop"
alias tmp="cd /tmp"

# Git
alias gclone="git clone"
alias gpush="git push"
alias gpull="git pull"
alias gaddall="git add -Av"
alias gcommit="git commit"
alias gcommitmsg="git commit -m "
alias gcheckout="git checkout"
alias gpushu="git push -u"
alias gresethard="git reset --hard"
alias gresetsoft="git reset --soft"
alias greset="git reset"

# Config
alias zshrc="nvim ~/.zshrc"

# Tmux
alias tmuxNew="tmux new -s"
alias tmuxList="tmux ls"
alias tmuxAttachLast="tmux a"
alias tmuxAttach="tmux a -t"
alias tmuxKill="tmux kill-session -t"

# gitlab-runner remote
remote-rpi() {
    ssh -i /usr/share/coder/fsp-dev-test-agent "coder@$1"
}

find-fuzzy() {
    # If a keyword is provided, pre-filter with fzf query; otherwise, open interactive list
    if [ -n "$1" ]; then
        find . -type f 2>/dev/null | fzf --query="$*"
    else
        find . -type f 2>/dev/null | fzf
    fi
}

#  * @brief Transfer files between local host and remote Raspberry Pi using rsync.
#  * @details Supports upload and download with an optional --type filter flag.
#  *
#  * @param --type Optional string of extensions to include (e.g., "*.srec *.yml").
#  * @param src Source path (local file or <ip>:<remote_path>).
#  * @param dst Destination path (local dir or <ip>:<remote_path>).
copy-rpi() {
    local key_path="/usr/share/coder/fsp-dev-test-agent"
    local file_types=""
    local src=""
    local dst=""
    
    # Store regex in a variable for cross-shell compatibility
    local ip_regex="^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:"

    # Parse command line arguments
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == "--type" ]]; then
            file_types="$2"
            shift 2
            
            # Proceed to the next argument iteration
            continue
        fi

        if [[ -z "$src" ]]; then
            src="$1"
        elif [[ -z "$dst" ]]; then
            dst="$1"
        else
            echo "Error: Too many arguments."
            
            # Exit function due to invalid argument count
            return 1
        fi
        
        shift
    done

    # Verify that both required paths are provided
    if [[ -z "$src" || -z "$dst" ]]; then
        echo "Usage: copy-rpi [--type \"*.srec *.yml\"] <src> <dst>"
        echo "Upload:   copy-rpi --type \"*.srec *.yml\" build/ 192.168.1.50:/home/coder"
        echo "Download: copy-rpi 192.168.1.50:/home/coder/project ."
        
        # Exit function due to missing arguments
        return 1
    fi

    # Prepend user "coder@" if the source specifies a remote host
    if [[ "$src" =~ $ip_regex ]]; then
        src="coder@$src"
    fi

    # Prepend user "coder@" if the destination specifies a remote host
    if [[ "$dst" =~ $ip_regex ]]; then
        dst="coder@$dst"
    fi

    # Initialize rsync arguments (-m prevents creating empty directories)
    local rsync_args=(-avzm -e "ssh -i $key_path")

    # Configure rsync include and exclude rules if types are specified
    if [[ -n "$file_types" ]]; then
        # Strictly quote glob patterns to prevent Zsh magic-equal-substitution
        rsync_args+=('--include=*/')
        
        while read -r ext; do
            if [[ -n "$ext" ]]; then
                rsync_args+=("--include=$ext")
            fi
        done <<< "$(echo "$file_types" | tr ' ' '\n')"
        
        # Strictly quote the wildcard exclude
        rsync_args+=('--exclude=*')
    fi

    # Display the intuitive src ---> dest mapping in terminal
    echo -e "\n\033[1;36m[COPY-RPI]\033[0m \033[1;32m$src\033[0m \033[1;33m--->\033[0m \033[1;32m$dst\033[0m\n"
    
    # Execute file transfer via rsync
    rsync "${rsync_args[@]}" "$src" "$dst"
}
