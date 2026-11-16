#!/bin/zsh
# Import and setup terminal configuration from this repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

# Machine → label and profiles mapping: single source of truth.
source "$SCRIPT_DIR/machine-label.sh"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Dev Environment Import ==="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    print "${RED}✗ This script is designed for macOS${NC}"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ask yes/no with default
# Usage: ask_yes_no "prompt" [default: y/n]
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local reply

    if [[ "$default" == "y" ]]; then
        read "reply?${prompt} [Y/n] "
        reply=${reply:-Y}
    else
        read "reply?${prompt} [y/N] "
        reply=${reply:-N}
    fi

    [[ "$reply" =~ ^[Yy]$ ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Homebrew (required - other steps depend on it)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 1: Homebrew ==="
if command_exists brew; then
    print "${GREEN}✓ Homebrew already installed${NC}"
else
    print "${YELLOW}→ Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    print "${GREEN}✓ Homebrew installed${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Brew Packages (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 2: Brew Bundle ==="
# Layers, each installed if present: the shared Brewfile, Brewfile.<primary profile>
# (the first profile machine-label.sh lists for this machine), then Brewfile.<label>.
# brew bundle is natively idempotent (skips installed, reports per-item).
BREW_LABEL="$MACHINE_LABEL"  # from machine-label.sh
BREW_LAYERS=(Brewfile)
[[ -n "$MACHINE_PRIMARY_PROFILE" && -f "Brewfile.$MACHINE_PRIMARY_PROFILE" ]] && BREW_LAYERS+=("Brewfile.$MACHINE_PRIMARY_PROFILE")
[[ -n "$BREW_LABEL" && -f "Brewfile.$BREW_LABEL" ]] && BREW_LAYERS+=("Brewfile.$BREW_LABEL")

if [ -f Brewfile ]; then
    [[ -z "$MACHINE_PRIMARY_PROFILE" ]] && print "${YELLOW}! Unknown machine — no profile or machine Brewfile, shared layer only${NC}"
    for layer in "${BREW_LAYERS[@]}"; do
        print "${BLUE}$layer:${NC} $(grep -cE '^(brew|cask|mas) ' "$layer") entries"
    done
    if ask_yes_no "Install brew dependencies (brew bundle: ${BREW_LAYERS[*]})?"; then
        for layer in "${BREW_LAYERS[@]}"; do
            brew bundle --file="$layer" || print "${RED}✗ some $layer entries failed${NC}"
        done
    else
        print "${YELLOW}! Skipped brew bundle${NC}"
    fi
else
    print "${RED}✗ Brewfile not found${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Nerd Font (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 3: asdf Runtimes ==="
# Per-machine pins (asdf/tool-versions.<label>) — same one-sided convention as
# .zshrc.<label>: this machine only ever reads its own file.
if [[ -n "$BREW_LABEL" ]] && [ -f "asdf/tool-versions.$BREW_LABEL" ] && command -v asdf >/dev/null 2>&1; then
    print "${BLUE}Runtimes ($BREW_LABEL):${NC} $(tr '\n' ' ' < "asdf/tool-versions.$BREW_LABEL")"
    if ask_yes_no "Install asdf plugins and runtimes? (runtime builds can take a while)"; then
        if [ -f ~/.tool-versions ]; then
            cp ~/.tool-versions ~/.tool-versions.backup-$(date +%Y%m%d-%H%M%S)
            print "${YELLOW}→ Backed up existing ~/.tool-versions${NC}"
        fi
        cp "asdf/tool-versions.$BREW_LABEL" ~/.tool-versions
        while read -r tool _version; do
            [[ -z "$tool" || "$tool" == \#* ]] && continue
            if asdf plugin list 2>/dev/null | grep -qx "$tool"; then
                print "${GREEN}✓ asdf plugin $tool already added${NC}"
            else
                print "${YELLOW}→ Adding asdf plugin $tool...${NC}"
                asdf plugin add "$tool" || print "${RED}✗ plugin $tool failed${NC}"
            fi
        done < "asdf/tool-versions.$BREW_LABEL"
        (cd ~ && asdf install) || print "${RED}✗ some runtimes failed to install${NC}"
    else
        print "${YELLOW}! Skipped asdf runtimes${NC}"
    fi
else
    print "${YELLOW}! No asdf/tool-versions.$BREW_LABEL in repo (or asdf missing), skipping${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Oh-My-Zsh (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 4: Oh-My-Zsh ==="
if [ -d ~/.oh-my-zsh ]; then
    print "${GREEN}✓ Oh-My-Zsh already installed${NC}"
else
    if ask_yes_no "Install Oh-My-Zsh?"; then
        print "${YELLOW}→ Installing Oh-My-Zsh...${NC}"
        if sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
            if [ -d ~/.oh-my-zsh ]; then
                print "${GREEN}✓ Oh-My-Zsh installed${NC}"
            else
                print "${RED}✗ Oh-My-Zsh installation failed (directory not created)${NC}"
            fi
        else
            print "${RED}✗ Oh-My-Zsh installation script failed${NC}"
        fi
    else
        print "${YELLOW}! Skipped Oh-My-Zsh${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Custom Plugins (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 5: Custom Plugins ==="
if [ ! -d ~/.oh-my-zsh ]; then
    print "${YELLOW}! Oh-My-Zsh not installed, skipping plugins${NC}"
elif [ ! -f plugins.list ]; then
    print "${RED}✗ plugins.list not found${NC}"
else
    print "${BLUE}Plugins: $(tr '\n' ' ' < plugins.list)${NC}"
    if ask_yes_no "Install custom plugins?"; then
        mkdir -p ~/.oh-my-zsh/custom/plugins

        # Plugin repository mapping
        declare -A PLUGIN_REPOS=(
            ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
            ["fast-syntax-highlighting"]="https://github.com/zdharma-continuum/fast-syntax-highlighting"
            ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab"
            ["alias-tips"]="https://github.com/djui/alias-tips"
            ["git-it-on"]="https://github.com/peterhurford/git-it-on.zsh"
            ["catimg"]="https://github.com/posva/catimg"
            ["auto-notify"]="https://github.com/MichaelAquilina/zsh-auto-notify"
            ["autoswitch_virtualenv"]="https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv"
            ["cd-ls"]="https://github.com/zshzoo/cd-ls"
            ["autoupdate"]="https://github.com/TamCore/autoupdate-oh-my-zsh-plugins"
            ["ls"]="https://github.com/zpm-zsh/ls"
        )

        while IFS= read -r plugin; do
            # Skip empty lines
            [[ -z "$plugin" ]] && continue

            plugin_dir=~/.oh-my-zsh/custom/plugins/$plugin

            if [ -d "$plugin_dir" ]; then
                print "${GREEN}✓ $plugin already installed${NC}"
            else
                if [ -n "${PLUGIN_REPOS[$plugin]}" ]; then
                    repo_url="${PLUGIN_REPOS[$plugin]}"

                    # Validate repository exists before cloning
                    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$repo_url" 2>/dev/null || echo "000")
                    if [ "$http_status" = "200" ]; then
                        print "${YELLOW}→ Installing $plugin...${NC}"
                        if git clone --quiet "$repo_url" "$plugin_dir" 2>/dev/null; then
                            print "${GREEN}✓ $plugin installed${NC}"
                        else
                            print "${RED}✗ $plugin failed to clone${NC}"
                        fi
                    else
                        print "${RED}✗ $plugin repository unavailable (HTTP $http_status): $repo_url${NC}"
                    fi
                else
                    print "${RED}✗ Unknown plugin: $plugin (no repo mapping)${NC}"
                fi
            fi
        done < plugins.list
    else
        print "${YELLOW}! Skipped custom plugins${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Homebrew command-not-found (informational only)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 6: Homebrew command-not-found ==="
print "${GREEN}✓ command-not-found is now built into Homebrew (no tap required)${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: FZF Integration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 7: FZF Integration ==="
if [ -f ~/.fzf.zsh ]; then
    print "${GREEN}✓ FZF already configured${NC}"
else
    FZF_INSTALL_PATH="$(brew --prefix 2>/dev/null)/opt/fzf/install"
    if [ -f "$FZF_INSTALL_PATH" ]; then
        if ask_yes_no "Setup FZF shell integration?"; then
            print "${YELLOW}→ Setting up FZF integration...${NC}"
            if "$FZF_INSTALL_PATH" --key-bindings --completion --no-update-rc --no-bash --no-fish; then
                print "${GREEN}✓ FZF configured${NC}"
            else
                print "${RED}✗ FZF configuration failed${NC}"
            fi
        else
            print "${YELLOW}! Skipped FZF integration${NC}"
        fi
    else
        print "${YELLOW}! FZF not installed (install with: brew install fzf)${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 8: Configuration Files (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 8: Configuration Files ==="

# Zsh split label comes from the shared mapping (machine-label.sh).
ZSH_LABEL="$MACHINE_LABEL"

# Check what config files exist in repo
HAS_CONFIG=false
[ -f .zshrc.base ] && HAS_CONFIG=true
[ -f .zshrc.full ] && HAS_CONFIG=true
[ -f .zshrc ] && HAS_CONFIG=true

if [ "$HAS_CONFIG" = false ]; then
    print "${RED}✗ No .zshrc config found in repo${NC}"
else
    # Show what will be copied
    print "${BLUE}Available configs:${NC}"
    if [ -f .zshrc.base ]; then
        echo "  - .zshrc.base  (shared)"
        [ -n "$ZSH_LABEL" ] && [ -f .zshrc.$ZSH_LABEL ] && echo "  - .zshrc.$ZSH_LABEL   (this machine only)"
        echo "  - .zshrc.loader → ~/.zshrc"
    fi
    [ -f .zshrc.full ] && echo "  - .zshrc.full  (legacy monolith)"
    [ -f .p10k.zsh ] && echo "  - .p10k.zsh"

    if ask_yes_no "Copy configuration files? (existing files will be backed up)"; then
        # Backup existing configs
        BACKUP_DIR=""
        if [ -f ~/.zshrc ] || [ -f ~/.zshrc.base ] || [ -f ~/.p10k.zsh ]; then
            BACKUP_DIR=~/.zsh-config-backup-$(date +%Y%m%d-%H%M%S)
            print "${YELLOW}→ Backing up existing configs to $BACKUP_DIR${NC}"
            mkdir -p "$BACKUP_DIR"
            for f in .zshrc .zshrc.base .zshrc.${ZSH_LABEL:-none} .zshrc.personal .p10k.zsh; do
                [ -f ~/$f ] && cp ~/$f "$BACKUP_DIR/$f"
            done
            print "${GREEN}✓ Existing configs backed up${NC}"
        fi

        # Determine which config files to use
        if [ -f .zshrc.base ]; then
            # Split layout: shared base + this machine's file + loader.
            # The OTHER machine's .zshrc.<label> is deliberately never touched.
            print "${YELLOW}→ Installing split zsh config${NC}"
            cp .zshrc.base ~/.zshrc.base
            print "${GREEN}✓ Copied ~/.zshrc.base${NC}"

            if [ -n "$ZSH_LABEL" ] && [ -f .zshrc.$ZSH_LABEL ]; then
                cp .zshrc.$ZSH_LABEL ~/.zshrc.$ZSH_LABEL
                print "${GREEN}✓ Copied ~/.zshrc.$ZSH_LABEL (this machine)${NC}"
            elif [ -z "$ZSH_LABEL" ]; then
                print "${YELLOW}! Unknown machine — installed base only, no machine-specific file${NC}"
            else
                print "${YELLOW}! No .zshrc.$ZSH_LABEL in repo — base installed without machine file${NC}"
            fi

            # Install the loader as ~/.zshrc (prefer the repo copy; fall back to inline)
            if [ -f .zshrc.loader ]; then
                cp .zshrc.loader ~/.zshrc
            else
                # NOTE: duplicates the machine-label.sh mapping by design —
                # see that file's header (shell startup can't depend on the repo).
                cat > ~/.zshrc << 'EOF'
[[ -f ~/.zshrc.base ]] && source ~/.zshrc.base
case "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" in
  mrtysn-mbp-m2max)  [[ -f ~/.zshrc.c02 ]] && source ~/.zshrc.c02 ;;
  mrtysn-mbp-m5)     [[ -f ~/.zshrc.c03 ]] && source ~/.zshrc.c03 ;;
esac
EOF
            fi
            print "${GREEN}✓ Installed ~/.zshrc loader${NC}"

        elif [ -f .zshrc.full ]; then
            # Legacy monolith
            print "${YELLOW}→ Copying .zshrc.full${NC}"
            cp .zshrc.full ~/.zshrc
            print "${GREEN}✓ Copied .zshrc${NC}"

        elif [ -f .zshrc ]; then
            # Legacy single file mode
            print "${YELLOW}→ Copying .zshrc${NC}"
            cp .zshrc ~/.zshrc
            print "${GREEN}✓ Copied .zshrc${NC}"
        fi

        # Copy .p10k.zsh
        if [ -f .p10k.zsh ]; then
            print "${YELLOW}→ Copying .p10k.zsh${NC}"
            cp .p10k.zsh ~/.p10k.zsh
            print "${GREEN}✓ Copied .p10k.zsh${NC}"
        fi
    else
        print "${YELLOW}! Skipped configuration files${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 9: iTerm2 Profiles & Settings (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 9: iTerm2 Profiles & Settings ==="
ITERM_DYNAMIC_PROFILES_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
PROFILES_DIR="$SCRIPT_DIR/iterm-profiles"

if [ ! -d "$PROFILES_DIR" ]; then
    print "${RED}✗ iterm-profiles directory not found${NC}"
elif ! command_exists defaults || ! defaults read com.googlecode.iterm2 &>/dev/null; then
    print "${YELLOW}! iTerm2 not installed or never opened, skipping profile setup${NC}"
else
    # List available profiles (exclude font-only for the full profiles option)
    FULL_PROFILES=("$PROFILES_DIR"/*.json(N))
    FULL_PROFILES=(${FULL_PROFILES:#*font-only.json})

    # Check what options are available
    HAS_FULL_PROFILES=false
    HAS_FONT_ONLY=false
    [[ ${#FULL_PROFILES[@]} -gt 0 ]] && HAS_FULL_PROFILES=true
    [[ -f "$PROFILES_DIR/font-only.json" ]] && HAS_FONT_ONLY=true

    if [[ "$HAS_FULL_PROFILES" = false && "$HAS_FONT_ONLY" = false ]]; then
        print "${YELLOW}! No iTerm2 profiles found in repo, skipping${NC}"
    else
        print "${BLUE}iTerm2 profile options:${NC}"
        if [[ "$HAS_FULL_PROFILES" = true ]]; then
            echo "  1) Full profiles - Import all profiles (colors, fonts, settings)"
        else
            echo "  1) [not available - no full profiles in repo]"
        fi
        if [[ "$HAS_FONT_ONLY" = true ]]; then
            echo "  2) Font only - Minimal profile that just sets FiraCode Nerd Font"
        else
            echo "  2) [not available - font-only.json missing]"
        fi
        echo "  3) Skip"
        echo ""
        read "iterm_choice?Select option [1/2/3]: "

        case "$iterm_choice" in
            1)
                if [[ "$HAS_FULL_PROFILES" = true ]]; then
                    print "${YELLOW}→ Installing full iTerm2 profiles...${NC}"
                    mkdir -p "$ITERM_DYNAMIC_PROFILES_DIR"
                    for profile in "${FULL_PROFILES[@]}"; do
                        filename=$(basename "$profile")
                        cp "$profile" "$ITERM_DYNAMIC_PROFILES_DIR/dev-config-$filename"
                        print "${GREEN}✓ Installed ${filename%.json}${NC}"
                    done
                    print "${BLUE}  Restart iTerm2 and select your preferred profile${NC}"
                else
                    print "${RED}✗ Full profiles not available${NC}"
                fi
                ;;
            2)
                if [[ "$HAS_FONT_ONLY" = true ]]; then
                    print "${YELLOW}→ Installing font-only profile...${NC}"
                    mkdir -p "$ITERM_DYNAMIC_PROFILES_DIR"
                    cp "$PROFILES_DIR/font-only.json" "$ITERM_DYNAMIC_PROFILES_DIR/dev-config-font-only.json"
                    print "${GREEN}✓ Font-only profile installed${NC}"
                    print "${BLUE}  Restart iTerm2 and select 'Dev Config (Font Only)' profile${NC}"
                else
                    print "${RED}✗ Font-only profile not available${NC}"
                fi
                ;;
            *)
                print "${YELLOW}! Skipped iTerm2 profiles${NC}"
                ;;
        esac
    fi

    # ── App-level settings ─────────────────────────────────────────────────────
    # Profiles only cover per-profile state. Theme, tab bar geometry, the Minimal
    # tuning knobs, global keymaps and pointer actions are top-level plist keys.
    ITERM_SETTINGS="$SCRIPT_DIR/iterm-settings.json"

    if [ ! -f "$ITERM_SETTINGS" ]; then
        print "${YELLOW}! iterm-settings.json not found, skipping app-level settings${NC}"
    elif ps -Ao comm= | grep -qE '(^|/)iTerm2$'; then
        # ps, not pgrep: pgrep can miss the process under some sandboxed shells,
        # and a false "not running" here means silently discarded settings.
        # iTerm rewrites its plist from memory on quit, so anything written now is
        # silently discarded. Refusing beats writing values that vanish.
        print "${RED}✗ iTerm2 is running — app-level settings NOT applied${NC}"
        print "${BLUE}  Quit iTerm2 completely, then re-run this script to apply them${NC}"
    else
        echo ""
        if ask_yes_no "Apply iTerm2 app-level settings (theme, tab bar, keymaps, pointer actions)?"; then
            print "${YELLOW}→ Applying iTerm2 app-level settings...${NC}"
            if python3 - "$ITERM_SETTINGS" <<'PYTHON_EOF'
import base64
import json
import os
import plistlib
import sys

settings_file = sys.argv[1]
plist_path = os.path.expanduser("~/Library/Preferences/com.googlecode.iterm2.plist")


def restore(obj):
    """Inverse of export.sh's convert_for_json."""
    if isinstance(obj, dict):
        if obj.get("_type") == "data" and "value" in obj:
            return base64.b64decode(obj["value"])
        return {k: restore(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [restore(item) for item in obj]
    return obj


try:
    with open(settings_file) as f:
        settings = restore(json.load(f).get("settings", {}))
except Exception as e:
    print(f"  Could not read {settings_file}: {e}", file=sys.stderr)
    sys.exit(1)

if not settings:
    print("  No settings found in the export, nothing to apply")
    sys.exit(0)

# Merge, don't replace: keys absent from the export (profiles, machine-local state)
# must survive untouched.
try:
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
except FileNotFoundError:
    plist = {}
except Exception as e:
    print(f"  Could not read existing plist: {e}", file=sys.stderr)
    sys.exit(1)

changed = [k for k, v in settings.items() if plist.get(k) != v]
plist.update(settings)

try:
    tmp = plist_path + ".tmp"
    with open(tmp, "wb") as f:
        plistlib.dump(plist, f)
    os.replace(tmp, plist_path)
except Exception as e:
    print(f"  Failed to write plist: {e}", file=sys.stderr)
    sys.exit(1)

print(f"  Applied {len(settings)} settings ({len(changed)} changed)")
for k in changed[:10]:
    print(f"    - {k}")
if len(changed) > 10:
    print(f"    ... and {len(changed) - 10} more")
PYTHON_EOF
            then
                # cfprefsd caches the domain; without this it can rewrite the old
                # values over the ones just written.
                killall cfprefsd 2>/dev/null || true
                print "${GREEN}✓ iTerm2 app-level settings applied${NC}"
                print "${BLUE}  Launch iTerm2 to see them${NC}"
            else
                print "${RED}✗ Failed to apply iTerm2 app-level settings${NC}"
            fi
        else
            print "${YELLOW}! Skipped iTerm2 app-level settings${NC}"
        fi
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 10: Default Shell (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 10: Default Shell ==="
if [ "$SHELL" = "/bin/zsh" ]; then
    print "${GREEN}✓ zsh is already the default shell${NC}"
else
    if ask_yes_no "Set zsh as default shell? (requires password)"; then
        print "${YELLOW}→ Setting zsh as default shell...${NC}"
        if chsh -s /bin/zsh; then
            print "${GREEN}✓ zsh set as default shell${NC}"
        else
            print "${RED}✗ Failed to set default shell (you can run 'chsh -s /bin/zsh' manually)${NC}"
        fi
    else
        print "${YELLOW}! Skipped setting default shell${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 11: Tmux Configuration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 11: Tmux Configuration ==="

if ! command_exists tmux; then
    print "${YELLOW}! tmux not installed, skipping (install with: brew install tmux)${NC}"
else
    # Machine label from the shared mapping (machine-label.sh).
    TMUX_CONF=""

    if [[ -n "$MACHINE_LABEL" ]]; then
        TMUX_CONF="tmux/$MACHINE_LABEL.conf"
    else
        print "${BLUE}Unknown machine (see machine-label.sh)${NC}"
        TMUX_CHOICES=(tmux/c[0-9][0-9].conf(N))
        for (( i = 1; i <= ${#TMUX_CHOICES[@]}; i++ )); do
            echo "  $i) ${TMUX_CHOICES[$i]:t:r}"
        done
        echo "  s) Skip"
        echo ""
        read "tmux_choice?Select machine config: "

        if [[ "$tmux_choice" == <-> ]] && (( tmux_choice >= 1 && tmux_choice <= ${#TMUX_CHOICES[@]} )); then
            TMUX_CONF="${TMUX_CHOICES[$tmux_choice]}"
            MACHINE_NAME="${TMUX_CONF:t:r}"
        else
            print "${YELLOW}! Skipped tmux configuration${NC}"
        fi
    fi

    if [[ -n "$TMUX_CONF" ]]; then
        print "${BLUE}Detected: $MACHINE_NAME${NC}"

        if ask_yes_no "Setup tmux configuration?"; then
            # Symlink tmux config
            TMUX_CONF_ABS="$SCRIPT_DIR/$TMUX_CONF"
            if [ -L ~/.tmux.conf ] && [ "$(readlink ~/.tmux.conf)" = "$TMUX_CONF_ABS" ]; then
                print "${GREEN}✓ ~/.tmux.conf already symlinked to $TMUX_CONF${NC}"
            else
                if [ -f ~/.tmux.conf ]; then
                    print "${YELLOW}→ Backing up existing ~/.tmux.conf${NC}"
                    cp ~/.tmux.conf ~/.tmux.conf.backup-$(date +%Y%m%d-%H%M%S)
                fi
                ln -sf "$TMUX_CONF_ABS" ~/.tmux.conf
                print "${GREEN}✓ Symlinked ~/.tmux.conf → $TMUX_CONF${NC}"
            fi

            # Copy sessions config example (only if not present)
            if [ ! -f ~/.tmux-sessions.conf ]; then
                cp "$SCRIPT_DIR/tmux/tmux-sessions.conf.example" ~/.tmux-sessions.conf
                print "${GREEN}✓ Created ~/.tmux-sessions.conf from example${NC}"
            else
                print "${GREEN}✓ ~/.tmux-sessions.conf already exists (kept)${NC}"
            fi

            # Append SSH config snippet (guarded by marker comment)
            SSH_MARKER="# --- Tmux Cross-SSH ---"
            if [ -f ~/.ssh/config ] && grep -qF "$SSH_MARKER" ~/.ssh/config; then
                print "${GREEN}✓ SSH config already contains tmux cross-SSH entries${NC}"
            else
                if ask_yes_no "Append tmux cross-SSH entries to ~/.ssh/config?"; then
                    mkdir -p ~/.ssh
                    chmod 700 ~/.ssh
                    echo "" >> ~/.ssh/config
                    cat "$SCRIPT_DIR/ssh/config.snippet" >> ~/.ssh/config
                    chmod 600 ~/.ssh/config
                    print "${GREEN}✓ Appended cross-SSH entries to ~/.ssh/config${NC}"
                    print "${YELLOW}  Note: Update C1-PLACEHOLDER and C2-PLACEHOLDER with actual IPs${NC}"
                else
                    print "${YELLOW}! Skipped SSH config${NC}"
                fi
            fi
        else
            print "${YELLOW}! Skipped tmux configuration${NC}"
        fi
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 12: Claude Code Settings (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 12: Claude Code Settings ==="

# Each config folder gets base settings.json + the overlays of the profile it declares in
# its paths.local.sh (AGENT_PROFILE). Folders come from settings-profile.sh dirs:
# $CLAUDE_CONFIG_DIRS when set, else ~/.claude and every ~/.claude-* holding settings.
SETTINGS_TOOL="$SCRIPT_DIR/agents/claude/settings-profile.sh"
WRITE_PATHS="$SCRIPT_DIR/agents/claude/write-paths-local.sh"

if ! command_exists jq; then
    print "${RED}✗ jq not installed — Claude settings are merged with jq (brew install jq), skipping${NC}"
else
    CLAUDE_DIRS=("${(@f)$("$SETTINGS_TOOL" dirs)}")
    print "${BLUE}Config folders:${NC} ${${CLAUDE_DIRS[@]/#$HOME/~}[*]}"
    print "${BLUE}This machine's profiles:${NC} ${MACHINE_PROFILES[*]:-none (unknown machine)}"
    while ask_yes_no "Add another Claude config folder (one per account)?" "n"; do
        read "extra_dir?Path, e.g. ~/.claude-work or ~/.claude-personal: "
        extra_dir="${extra_dir/#\~/$HOME}"
        [[ -n "$extra_dir" ]] && CLAUDE_DIRS+=("${extra_dir%/}")
    done

    for target_dir in "${CLAUDE_DIRS[@]}"; do
        target="$target_dir/settings.json"
        shown="${target_dir/#$HOME/~}"
        echo ""
        print "${BLUE}── $shown${NC}"

        if [ ! -d "$target_dir" ] && ! ask_yes_no "$shown does not exist — create it?" "n"; then
            print "${YELLOW}! Skipped $shown${NC}"
            continue
        fi

        # The profile is the folder's own declaration; ask only when it has none.
        profile="$("$SETTINGS_TOOL" profile "$target_dir")"
        if [[ -z "$profile" ]]; then
            # ~/.claude takes the machine's primary profile; another folder the next one.
            suggested="${MACHINE_PRIMARY_PROFILE:-personal}"
            if [[ "$target_dir" != "$HOME/.claude" && ${#MACHINE_PROFILES[@]} -gt 1 ]]; then
                suggested="${MACHINE_PROFILES[2]}"
            fi
            read "profile?Profile for $shown (${MACHINE_PROFILES[*]:-personal work}) [$suggested]: "
            profile="${profile:-$suggested}"
        fi
        if (( ${#MACHINE_PROFILES[@]} )) && (( ! ${MACHINE_PROFILES[(Ie)$profile]} )); then
            print "${YELLOW}! $shown declares profile '$profile', which machine-label.sh does not list for $MACHINE_LABEL${NC}"
        fi

        # paths.local.sh first: it records the profile, and the guard hooks in the merged
        # settings exit 2 — refusing every Bash tool call — until it resolves agents-shared.
        mkdir -p "$target_dir"
        if ! CLAUDE_DIR="$target_dir" "$WRITE_PATHS" --profile "$profile"; then
            print "${YELLOW}! paths.local.sh in $shown does not resolve agents-shared — Claude Code will refuse Bash tool calls there until it does${NC}"
            print "${YELLOW}  Fix with: CLAUDE_DIR=$shown agents/claude/write-paths-local.sh --profile $profile --path <agents-shared checkout>${NC}"
        fi

        if ! merged="$("$SETTINGS_TOOL" merge "$profile")"; then
            print "${RED}✗ Could not build settings for profile '$profile' — $shown left as it is${NC}"
            continue
        fi
        print "${BLUE}Settings:${NC} base + $("$SETTINGS_TOOL" overlays "$profile" | sed "s|^$SCRIPT_DIR/||" | tr '\n' ' ')"

        if [ -f "$target" ] && "$SETTINGS_TOOL" check "$target_dir" "$profile" >/dev/null 2>&1; then
            print "${GREEN}✓ $shown/settings.json already matches${NC}"
            continue
        fi
        if ! ask_yes_no "Write $shown/settings.json for profile '$profile'? (backed up first)" "y"; then
            print "${YELLOW}! Skipped $shown${NC}"
            continue
        fi

        # env.AGENTS_SHARED is this machine's checkout path, written by agents-shared's
        # init-global.sh and stripped on export; carry the live value over.
        local_shared=""
        if [ -f "$target" ]; then
            local_shared="$(jq -r '.env.AGENTS_SHARED // empty' "$target" 2>/dev/null || true)"
            cp "$target" "$target.backup-$(date +%Y%m%d-%H%M%S)"
            print "${YELLOW}→ Backed up existing $target${NC}"
        fi
        if print -r -- "$merged" | jq --arg p "$local_shared" 'if $p != "" then .env.AGENTS_SHARED = $p else . end' > "$target.tmp"; then
            mv "$target.tmp" "$target"
            print "${GREEN}✓ Wrote $target (base + $profile)${NC}"
            [[ -z "$local_shared" ]] && print "${YELLOW}  Run agents-shared/scripts/init-global.sh to set env.AGENTS_SHARED here${NC}"
        else
            rm -f "$target.tmp"
            print "${RED}✗ Failed to write $target${NC}"
        fi
    done
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 13: Window & Keyboard Configs (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 13: Window & Keyboard Configs ==="

HAS_WK=false
[ -f .phoenix.js ] && HAS_WK=true
[ -f karabiner/karabiner.json ] && HAS_WK=true

if [ "$HAS_WK" = false ]; then
    print "${YELLOW}! No Phoenix/Karabiner configs in repo, skipping${NC}"
else
    print "${BLUE}Available configs:${NC}"
    [ -f .phoenix.js ] && echo "  - .phoenix.js → ~/.phoenix.js (Phoenix window manager)"
    [ -f karabiner/karabiner.json ] && echo "  - karabiner/karabiner.json → ~/.config/karabiner/karabiner.json (Karabiner keymaps)"

    if ask_yes_no "Copy window & keyboard configs? (existing files will be backed up)"; then
        if [ -f .phoenix.js ]; then
            if [ -f ~/.phoenix.js ]; then
                cp ~/.phoenix.js ~/.phoenix.js.backup-$(date +%Y%m%d-%H%M%S)
                print "${YELLOW}→ Backed up existing ~/.phoenix.js${NC}"
            fi
            cp .phoenix.js ~/.phoenix.js
            print "${GREEN}✓ Copied ~/.phoenix.js${NC}"
        fi

        if [ -f karabiner/karabiner.json ]; then
            mkdir -p ~/.config/karabiner
            if [ -f ~/.config/karabiner/karabiner.json ]; then
                cp ~/.config/karabiner/karabiner.json ~/.config/karabiner/karabiner.json.backup-$(date +%Y%m%d-%H%M%S)
                print "${YELLOW}→ Backed up existing ~/.config/karabiner/karabiner.json${NC}"
            fi
            cp karabiner/karabiner.json ~/.config/karabiner/karabiner.json
            print "${GREEN}✓ Copied ~/.config/karabiner/karabiner.json${NC}"
            print "${BLUE}  Restart Karabiner-Elements to apply${NC}"
        fi
    else
        print "${YELLOW}! Skipped window & keyboard configs${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 14: lazygit + repo-tabs Configuration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 14: lazygit + repo-tabs Configuration ==="

LAZYGIT_DIR="$HOME/Library/Application Support/lazygit"
HAS_LG=false
[ -f lazygit/config.yml ] && HAS_LG=true
[ -d repo-tabs ] && HAS_LG=true

if [ "$HAS_LG" = false ]; then
    print "${YELLOW}! No lazygit/repo-tabs configs in repo, skipping${NC}"
else
    print "${BLUE}Available configs:${NC}"
    [ -f lazygit/config.yml ] && echo "  - lazygit/config.yml + themes → $LAZYGIT_DIR/"
    [ -d repo-tabs ] && echo "  - repo-tabs/theme-* → ~/.config/repo-tabs/ (group themes for repo-tabs lazy)"

    if ask_yes_no "Copy lazygit & repo-tabs configs? (existing files will be backed up)"; then
        if [ -f lazygit/config.yml ]; then
            mkdir -p "$LAZYGIT_DIR/themes"
            if [ -f "$LAZYGIT_DIR/config.yml" ]; then
                cp "$LAZYGIT_DIR/config.yml" "$LAZYGIT_DIR/config.yml.backup-$(date +%Y%m%d-%H%M%S)"
                print "${YELLOW}→ Backed up existing lazygit config.yml${NC}"
            fi
            cp lazygit/config.yml "$LAZYGIT_DIR/config.yml"
            for t in lazygit/themes/*.yml(N); do
                cp "$t" "$LAZYGIT_DIR/themes/${t:t}"
            done
            print "${GREEN}✓ Copied lazygit config + themes${NC}"
        fi
        if [ -d repo-tabs ]; then
            mkdir -p ~/.config/repo-tabs
            for g in repo-tabs/theme-*(N); do
                cp "$g" ~/.config/repo-tabs/"${g:t}"
            done
            print "${GREEN}✓ Copied repo-tabs group themes${NC}"
            print "${BLUE}  repos.txt is machine-local — seed it with 'repo-tabs focus' on first run${NC}"
        fi
    else
        print "${YELLOW}! Skipped lazygit & repo-tabs configs${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 15: Push name guard for this repo (optional)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Step 15: Push Name Guard ==="
# This repo is public. agents-shared's githooks/pre-push reads every commit a push sends
# and refuses it when an added line, path or message names an entry on a local, untracked
# denylist (an employer, a client); an empty denylist passes everything, so this step warns on one. Opting in points this clone's core.hooksPath at it.
# By hand: git -C <this repo> config core.hooksPath "$AGENTS_SHARED/githooks"
GUARD_SHARED="${AGENTS_SHARED:-}"
if [[ -z "$GUARD_SHARED" && -r "$HOME/.claude/paths.local.sh" ]]; then
    GUARD_SHARED="$(AGENTS_SHARED_DIR=""; . "$HOME/.claude/paths.local.sh" >/dev/null 2>&1; print -r -- "${AGENTS_SHARED_DIR:-}")"
fi
[[ -z "$GUARD_SHARED" && -d "${SCRIPT_DIR:h}/agents-shared" ]] && GUARD_SHARED="${SCRIPT_DIR:h}/agents-shared"
GUARD_HOOKS="${GUARD_SHARED:+$GUARD_SHARED/githooks}"
GUARD_LIST="${AGENTS_PUSH_DENYLIST:-${XDG_CONFIG_HOME:-$HOME/.config}/agents-shared/push-denylist.txt}"

if [[ -z "$GUARD_SHARED" ]]; then
    print "${RED}✗ No agents-shared checkout found (\$AGENTS_SHARED, ~/.claude/paths.local.sh or a sibling of this repo) — name guard not installed${NC}"
elif [[ ! -x "$GUARD_HOOKS/pre-push" ]]; then
    print "${RED}✗ $GUARD_HOOKS/pre-push is missing or not executable — pull agents-shared, then re-run this step${NC}"
elif [[ "$(git -C "$SCRIPT_DIR" config --get core.hooksPath || true)" == "$GUARD_HOOKS" ]]; then
    print "${GREEN}✓ Pushes from this clone already go through $GUARD_HOOKS/pre-push${NC}"
else
    existing_hooks="$(git -C "$SCRIPT_DIR" config --get core.hooksPath || true)"
    [[ -n "$existing_hooks" ]] && print "${YELLOW}! core.hooksPath is currently $existing_hooks; it will be replaced${NC}"
    if ask_yes_no "Route this clone's pushes through the name guard ($GUARD_HOOKS/pre-push)?"; then
        git -C "$SCRIPT_DIR" config core.hooksPath "$GUARD_HOOKS"
        print "${GREEN}✓ core.hooksPath → $GUARD_HOOKS${NC}"
    else
        print "${YELLOW}! Skipped the name guard${NC}"
    fi
fi
if [[ "$(git -C "$SCRIPT_DIR" config --get core.hooksPath || true)" == "${GUARD_HOOKS:-none}" ]]; then
    if [[ ! -r "$GUARD_LIST" ]]; then
        print "${YELLOW}! $GUARD_LIST does not exist, so every push is refused until it does:${NC}"
        print "${YELLOW}  copy $GUARD_HOOKS/push-denylist.txt.example there and add one name per line${NC}"
    elif [[ -z "$(grep -Ev '^[[:space:]]*(#|$)' "$GUARD_LIST" || true)" ]]; then
        # The hook passes with an empty list, so the guard looks installed while it blocks nothing.
        print "${RED}✗ $GUARD_LIST holds no entries (only comments or blank lines): the name guard blocks NOTHING.${NC}"
        print "${RED}  Add one name per line (an employer, a client; see $GUARD_HOOKS/push-denylist.txt.example) before the next push.${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Complete
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Import Complete ==="
echo ""
print "${GREEN}✓ Setup finished${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Powerlevel10k config wizard will run on first start (if not configured)"
echo "  3. Machine-specific aliases live in ~/.zshrc.<label> (c02 Home, c03 Work); shared config in ~/.zshrc.base"
echo ""
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo "Your old configs are backed up at: $BACKUP_DIR"
    echo ""
fi
