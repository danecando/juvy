# Comprehensive test zshrc
export PATH="/usr/local/bin:$PATH"
export EDITOR="nvim"

# Aliases
alias ll="ls -la"
alias grep="grep --color=auto"
alias vim="nvim"

# History settings
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# Zsh options
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY