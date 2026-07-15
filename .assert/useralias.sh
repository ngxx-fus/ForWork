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