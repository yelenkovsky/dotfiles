set -g fish_greeting

# Proton Pass desktop SSH agent (do not hardcode the home path)
set -gx SSH_AUTH_SOCK $HOME/.ssh/proton-pass-ssh-agent.sock

# pass-cli and other user binaries (must be on PATH before interactive pass-cli calls)
fish_add_path $HOME/.local/bin

if status is-interactive
    starship init fish | source

    fzf --fish | source

    # Enable vim bindings
    fish_vi_key_bindings
    
    # Environment variables
    set -x EZA_CONFIG_DIR ~/.config/eza

    # API keys from Proton Pass (requires an active pass-cli session)
    set -x PROTON_PASS_SESSION_DIR ~/.local/share/proton-pass-session
    set -gx OPENROUTER_API_KEY (PROTON_PASS_AGENT_REASON="Load OpenRouter key into shell env" pass-cli item view --vault-name ai --item-title openrouter --field "API Key" 2>/dev/null)
    set -gx OPENROUTER_BASE_URL https://eu.openrouter.ai/api/v1
    set -gx CURSOR_API_KEY (PROTON_PASS_AGENT_REASON="Load Cursor key into shell env" pass-cli item view --vault-name ai --item-title cursor --field "API Key" 2>/dev/null)
    set -gx TODOIST_API_KEY (PROTON_PASS_AGENT_REASON="Load Todoist key into shell env" pass-cli item view --vault-name ai --item-title todoist --field "API Key" 2>/dev/null)
    set -gx AZURE_SPEECH_KEY (PROTON_PASS_AGENT_REASON="Load Azure Speech key into shell env" pass-cli item view --vault-name ai --item-title azurespeech --field "API Key" 2>/dev/null)

    # Aliases
    alias fishconfig='xdg-open ~/.config/fish/config.fish'

    # eza
    alias l='eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first'
    alias ll='eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first -l --git -h'
    alias la='eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first -a'
    alias lla='eza --color=always --color-scale=all --color-scale-mode=gradient --icons=always --group-directories-first -a -l --git -h'

    # terminal commands
    alias ping='ping 1.1.1.1'
    
    # open
    alias sf="source ~/.config/fish/config.fish"
end
