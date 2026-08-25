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

copy-rpi() {
    local key_path="/usr/share/coder/fsp-dev-test-agent"
    local file_types=""
    local src=""
    local dst=""

    # Parse command line arguments
    while [[ "$#" -gt 0 ]]; do
        # Check if current argument is the type flag
        if [[ "$1" == "--type" ]]; then
            file_types="$2"
            shift 2
            
            # Proceed to the next argument iteration
            continue
        fi

        # Assign source path if it is empty
        if [[ -z "$src" ]]; then
            src="$1"
        # Assign destination path if source is already set
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
    if [[ "$src" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
        src="coder@$src"
    fi

    # Prepend user "coder@" if the destination specifies a remote host
    if [[ "$dst" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
        dst="coder@$dst"
    fi

    local rsync_args=(-avz -e "ssh -i $key_path")

    # Configure rsync include and exclude rules if types are specified
    if [[ -n "$file_types" ]]; then
        rsync_args+=("--include=*/")
        
        # Iterate through each specified extension
        while read -r ext; do
            # Add include rule for non-empty extensions
            if [[ -n "$ext" ]]; then
                rsync_args+=("--include=$ext")
            fi
        done <<< "$(echo "$file_types" | tr ' ' '\n')"
        
        rsync_args+=("--exclude=*")
    fi

    # Execute file transfer via rsync
    rsync "${rsync_args[@]}" "$src" "$dst"
}
