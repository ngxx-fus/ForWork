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
    # Check if both source and destination arguments are provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: copy-rpi <src> <dst>"
        echo "Example (Upload):   copy-rpi main.c 192.168.1.50:/home/coder"
        echo "Example (Download): copy-rpi 192.168.1.50:/home/coder/main.c ."
        # Exit with error status when arguments are missing
        return 1
    fi

    local key_path="/usr/share/coder/fsp-dev-test-agent"
    local src="$1"
    local dst="$2"

    # Prepend user "coder@" if the argument specifies a remote host
    if [[ "$src" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
        src="coder@$src"
    fi

    # Prepend user "coder@" if the destination specifies a remote host
    if [[ "$dst" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+: ]]; then
        dst="coder@$dst"
    fi

    # Execute secure copy
    scp -i "$key_path" -r "$src" "$dst"
}
