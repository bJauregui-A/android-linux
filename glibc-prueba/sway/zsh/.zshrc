# zsh como la de HyDE en el PC, sin oh-my-zsh (no está en los repos de Arch ARM):
# prompt de starship con el starship.toml del PC, autosugerencias, colores de sintaxis,
# historial compartido y fastfetch al abrir. Lo copia scripts/subir-sway.sh a ~/.zshrc.

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt share_history hist_ignore_all_dups hist_ignore_space extended_history
setopt auto_cd interactive_comments

bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

autoload -Uz compinit && compinit -d ~/.cache/zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ESC dos veces antepone sudo (plugin "sudo" de oh-my-zsh)
_antepone_sudo() { [[ $BUFFER == sudo\ * ]] && BUFFER=${BUFFER#sudo } || BUFFER="sudo $BUFFER"; CURSOR=$#BUFFER; }
zle -N _antepone_sudo
bindkey '\e\e' _antepone_sudo

eval "$(dircolors -b)"
alias ls='ls --color=auto' grep='grep --color=auto' diff='diff --color=auto'
alias l='ls -lh' ll='ls -lha' c='clear' ..='cd ..' ...='cd ../..' mkdir='mkdir -p'
alias fastfetch='fastfetch --logo-type kitty'
command -v eza >/dev/null && alias ls='eza -1 --icons=auto' l='eza -lh --icons=auto' \
    ll='eza -lha --icons=auto --sort=name --group-directories-first' lt='eza --icons=auto --tree'

export STARSHIP_CONFIG=~/.config/starship/starship.toml STARSHIP_CACHE=~/.cache/starship
command -v starship >/dev/null && eval "$(starship init zsh)"

for p in /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    [[ -r $p ]] && source $p
done

# fastfetch al abrir, como HyDE. En el teléfono (~40 columnas) el logo grande parte las
# líneas: logo chico arriba y solo los datos cortos (Shell/WM dirían libldp.so).
if [[ $TERM == xterm-kitty ]] && command -v fastfetch >/dev/null; then
    if (( COLUMNS < 80 )); then
        fastfetch --logo arch_small --logo-position top \
            --structure Title:OS:Uptime:Packages:CPU:GPU:Memory:Colors
    else
        fastfetch --logo-type kitty
    fi
fi
