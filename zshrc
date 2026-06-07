alias ls='eza --icons'
alias cat='bat'
alias pbcopy='wl-copy'
alias pbpaste='wl-paste'
alias reload-caelestia='pkill -f "qs -c caelestia"; caelestia shell -d'

eval "$(starship init zsh)"
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

autoload -U compinit; compinit
source ~/.zsh/fzf-tab/fzf-tab.plugin.zsh

# Sourcing Atuin environment and initializing it if available
if [ -f "$HOME/.atuin/bin/env" ]; then
    source "$HOME/.atuin/bin/env"
fi
if command -v atuin &>/dev/null; then
    eval "$(atuin init zsh)"
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export DOCKER_HOST=unix:///var/run/docker.sock

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
#export PATH="/home/jesdev12u/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export ANDROID_NDK_ROOT=/opt/android-ndk

# Created by `pipx` on 2026-03-20 06:45:20
export PATH="$PATH:/home/jesdev12u/.local/bin"
export PATH="$HOME/.cargo/bin:$PATH"

# OpenClaw Completion
#source "/home/jesdev12u/.openclaw/completions/openclaw.zsh"
