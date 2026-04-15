#!/bin/zsh
# Export current terminal configuration to this repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
cd "$SCRIPT_DIR"

HOSTNAME=$(hostname -s)
USERNAME=$(whoami)
DATE=$(date +"%Y-%m-%d %H:%M")

echo "=== Exporting dev environment configuration ==="
echo ""
echo "Computer: $HOSTNAME"
echo "User: $USERNAME"
echo ""
echo "This will export your ~/.zshrc, ~/.p10k.zsh, tmux config, and iTerm2 profiles to this repository."
echo ""
echo "Files in this repo that will be overwritten:"
echo "  - $SCRIPT_DIR/.zshrc.full"
echo "  - $SCRIPT_DIR/.p10k.zsh"
echo "  - $SCRIPT_DIR/plugins.list"
echo "  - $SCRIPT_DIR/brew-packages.list"
echo "  - $SCRIPT_DIR/iterm-profiles/*.json"
echo "  - $SCRIPT_DIR/tmux/c1.conf or c2.conf (based on hostname)"
echo "  - $SCRIPT_DIR/bin/tgo, bin/tmux-start"
echo ""
echo "Your actual config files will NOT be modified."
echo ""
read "REPLY?Continue? (y/N) "
REPLY=${REPLY:-N}
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Export cancelled."
    exit 0
fi
echo ""

# Clean up old split files (no longer used)
echo "✓ Cleaning up old config files"
rm -f .zshrc.full .zshrc.base .zshrc.personal
echo ""

# Export .zshrc
if [ -f ~/.zshrc ]; then
    echo "✓ Exporting ~/.zshrc"
    cp ~/.zshrc .zshrc.full
else
    echo "✗ ~/.zshrc not found"
    exit 1
fi

# Export .p10k.zsh
if [ -f ~/.p10k.zsh ]; then
    echo "✓ Exporting ~/.p10k.zsh"
    cp ~/.p10k.zsh .p10k.zsh
else
    echo "✗ ~/.p10k.zsh not found"
    exit 1
fi

# Export custom plugin list
echo "✓ Scanning custom plugins"
if [ -d ~/.oh-my-zsh/custom/plugins ]; then
    find ~/.oh-my-zsh/custom/plugins -maxdepth 1 -type d -not -name "plugins" -not -name "example" | \
        xargs -I {} basename {} > plugins.list.tmp

    grep -v '^$' plugins.list.tmp > plugins.list || touch plugins.list
    rm plugins.list.tmp

    echo "  Found $(wc -l < plugins.list | tr -d ' ') custom plugins"
else
    echo "  No custom plugins directory found"
    touch plugins.list
fi

# Write brew package dependencies (static list, not scanned from system)
# These are packages required by the dev environment:
#   powerlevel10k - prompt theme (sourced in zshrc)
#   fzf           - fuzzy finder (fzf --zsh integration + fzf-tab plugin)
#   asdf          - version manager (paths, commands, plugin)
#   coreutils     - GNU utilities (gnubin in PATH)
#   tree          - directory tree (used by ls plugin)
#   tmux          - terminal multiplexer
echo "✓ Writing brew package dependencies"
cat > brew-packages.list << 'EOF'
powerlevel10k
fzf
asdf
coreutils
tree
tmux
EOF

# Export tmux config
echo "✓ Exporting tmux configuration"
MACHINE_HOSTNAME=$(hostname -s)
TMUX_TARGET=""

if [[ "$MACHINE_HOSTNAME" == "mert-cypher-m3max" ]]; then
    TMUX_TARGET="tmux/c1.conf"
    echo "  Detected: C1 (Office)"
elif [[ "$MACHINE_HOSTNAME" == "mrtysn-mbp-m2max" ]]; then
    TMUX_TARGET="tmux/c2.conf"
    echo "  Detected: C2 (Home)"
else
    echo "  Unknown hostname: $MACHINE_HOSTNAME, skipping tmux config export"
fi

if [[ -n "$TMUX_TARGET" ]]; then
    mkdir -p tmux bin

    if [ -f ~/.tmux.conf ]; then
        # Resolve symlink to get actual content
        cp -L ~/.tmux.conf "$TMUX_TARGET"
        echo "  Exported ~/.tmux.conf → $TMUX_TARGET"
    else
        echo "  ~/.tmux.conf not found, skipping"
    fi

    if [ -f ~/bin/tgo ]; then
        cp ~/bin/tgo bin/tgo
        chmod +x bin/tgo
        echo "  Exported ~/bin/tgo"
    else
        echo "  ~/bin/tgo not found, skipping"
    fi

    if [ -f ~/bin/tmux-start ]; then
        cp ~/bin/tmux-start bin/tmux-start
        chmod +x bin/tmux-start
        echo "  Exported ~/bin/tmux-start"
    else
        echo "  ~/bin/tmux-start not found, skipping"
    fi
fi

# Export iTerm2 profiles
echo "✓ Exporting iTerm2 profiles"
mkdir -p iterm-profiles

ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

if [ ! -f "$ITERM_PLIST" ]; then
    echo "  iTerm2 not installed, skipping"
elif ! defaults read com.googlecode.iterm2 &>/dev/null; then
    echo "  iTerm2 preferences not readable, skipping"
else
    python3 << 'PYTHON_EOF' || echo "  Failed to export iTerm2 profiles"
import plistlib
import json
import os
import sys

plist_path = os.path.expanduser("~/Library/Preferences/com.googlecode.iterm2.plist")
output_dir = "iterm-profiles"

def convert_for_json(obj):
    if isinstance(obj, bytes):
        import base64
        return {"_type": "data", "value": base64.b64encode(obj).decode('ascii')}
    elif isinstance(obj, dict):
        return {k: convert_for_json(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_for_json(item) for item in obj]
    else:
        return obj

def name_to_filename(name):
    return name.lower().replace(" ", "-") + ".json"

try:
    with open(plist_path, 'rb') as f:
        data = plistlib.load(f)
except Exception as e:
    print(f"  Could not read iTerm2 plist: {e}", file=sys.stderr)
    sys.exit(1)

profiles = data.get("New Bookmarks", [])
if not profiles:
    print("  No profiles found in iTerm2")
    sys.exit(0)

exported = 0
for profile in profiles:
    name = profile.get("Name", "Unknown")
    filename = name_to_filename(name)
    filepath = os.path.join(output_dir, filename)

    dynamic_profile = {
        "Profiles": [convert_for_json(profile)]
    }

    try:
        with open(filepath, 'w') as f:
            json.dump(dynamic_profile, f, indent=2)
        print(f"  - {name} -> {filename}")
        exported += 1
    except Exception as e:
        print(f"  Failed to write {filename}: {e}", file=sys.stderr)

print(f"  Exported {exported} profiles")
PYTHON_EOF
fi

# Create font-only profile if it doesn't exist
if [ ! -f iterm-profiles/font-only.json ]; then
    echo "✓ Creating font-only profile template"
    cat > iterm-profiles/font-only.json << 'EOF'
{
  "Profiles": [
    {
      "Name": "Dev Config (Font Only)",
      "Guid": "DEV-CONFIG-FONT-ONLY-0001",
      "Dynamic Profile Parent Name": "Default",
      "Normal Font": "FiraCodeNFM-Reg 12",
      "Use Non-ASCII Font": false
    }
  ]
}
EOF
fi

# Log export to EXPORTS.md
echo "✓ Logging export"
if [ ! -f EXPORTS.md ]; then
    cat > EXPORTS.md << 'EOF'
# Export History

| Date | Computer | User |
|------|----------|------|
EOF
fi

echo "| $DATE | $HOSTNAME | $USERNAME |" >> EXPORTS.md

echo ""
echo "=== Export complete ==="
echo ""
echo "Files exported:"
echo "  - $SCRIPT_DIR/.zshrc.full"
echo "  - $SCRIPT_DIR/.p10k.zsh"
echo "  - $SCRIPT_DIR/plugins.list"
echo "  - $SCRIPT_DIR/brew-packages.list"
echo "  - $SCRIPT_DIR/iterm-profiles/*.json"
if [[ -n "${TMUX_TARGET:-}" ]]; then
echo "  - $SCRIPT_DIR/$TMUX_TARGET"
echo "  - $SCRIPT_DIR/bin/tgo"
echo "  - $SCRIPT_DIR/bin/tmux-start"
fi
echo "  - $SCRIPT_DIR/EXPORTS.md (updated)"
echo ""
echo "Next steps:"
echo "  1. Review the exported files: git diff"
echo "  2. Commit and push changes: git add . && git commit && git push"
