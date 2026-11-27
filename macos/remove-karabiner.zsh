#!/bin/zsh
# Find and remove what Karabiner-Elements leaves on a Mac. dev-env maps the keys with macOS's own
# settings (step 18), so a Mac keeps none of it.
#   remove-karabiner.zsh           remove what can be removed; sudo asks for a password once
#   remove-karabiner.zsh --check   list what is left (exit 1 if anything)
# `brew uninstall --cask` removes the app and its packages but not its driver extension, and the
# driver can only be deactivated by Karabiner's own uninstaller while the app is installed
# (systemextensionsctl uninstall refuses while System Integrity Protection is on). So when only the
# driver is left, this says to reinstall the cask, run that uninstaller, and run this again.
# Daemons left running from a deleted app stop at the next restart.
set -u -o pipefail
CASK=karabiner-elements
APP=/Applications/Karabiner-Elements.app
# The cask's uninstall and zap paths (brew info --cask --json=v2 karabiner-elements).
USER_PATHS=(
    "$HOME/.config/karabiner"
    "$HOME/.local/share/karabiner"
    "$HOME/Library/Application Scripts/org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    "$HOME/Library/Application Support/Karabiner-Elements"
    "$HOME/Library/Caches/org.pqrs.Karabiner-Elements.Updater"
    "$HOME/Library/Containers/org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    "$HOME/Library/HTTPStorages/org.pqrs.Karabiner-Elements.Settings"
    "$HOME/Library/Preferences/org.pqrs.Karabiner-Elements.Settings.plist"
    "$HOME/Library/Preferences/org.pqrs.Karabiner-Elements.Updater.plist"
    "$HOME/Library/Preferences/org.pqrs.Karabiner-EventViewer.plist"
)
SYSTEM_PATHS=("/Library/Application Support/org.pqrs")

cask_installed() { command -v brew >/dev/null && brew list --cask $CASK >/dev/null 2>&1; }
driver_active() { systemextensionsctl list 2>/dev/null | grep 'org.pqrs' | grep -q 'activated'; }
# Services with a pid in launchctl's services list; its "disabled services" list keeps every label a
# past version registered, running or not.
running_jobs() {
    { launchctl print system; launchctl print "gui/$(id -u)"; } 2>/dev/null \
        | sed -nE 's/^[[:space:]]+[0-9]+[[:space:]]+[-0-9]+[[:space:]]+(org\.pqrs[A-Za-z0-9._-]*)$/\1/p' | sort -u
}
left_paths() {
    local p
    for p in $USER_PATHS $SYSTEM_PATHS; do [[ -e "$p" ]] && print -r -- "$p"; done
}

report() {
    local found=0 p j
    [[ -d $APP ]] && { print "  app: $APP"; found=1; }
    cask_installed && { print "  brew cask: $CASK"; found=1; }
    driver_active && { print "  driver extension: org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (active)"; found=1; }
    for j in ${(f)"$(running_jobs)"}; do print "  running service: $j"; found=1; done
    for p in ${(f)"$(left_paths)"}; do print "  file: $p"; found=1; done
    return $found
}

if [[ "${1:-}" == --check ]]; then
    out=$(report); found=$?
    if (( found )); then
        print "✗ Karabiner-Elements is still on this Mac:"
        print -r -- "$out"
        exit 1
    fi
    print "✓ no Karabiner-Elements left on this Mac"
    exit 0
fi

if cask_installed; then
    brew uninstall --cask --zap $CASK || print "✗ brew could not uninstall $CASK"
fi
for p in $USER_PATHS; do
    [[ -e "$p" ]] && { rm -rf -- "$p" && print "✓ removed $p" || print "✗ could not remove $p"; }
done
for p in $SYSTEM_PATHS; do
    [[ -e "$p" ]] && { sudo rm -rf -- "$p" && print "✓ removed $p" || print "✗ could not remove $p"; }
done
if driver_active; then
    print "✗ Karabiner's driver extension is still active. Only Karabiner's own uninstaller removes it:"
    print "  brew install --cask $CASK, then Karabiner-Elements > Settings > Misc > Uninstall Karabiner-Elements,"
    print "  then run this step again."
fi
jobs=$(running_jobs)
if [[ -n $jobs ]]; then
    print "! Karabiner services still running from the deleted app; they stop at the next restart:"
    for j in ${(f)jobs}; do print -r -- "  $j"; done
fi
out=$(report)
if [[ -z $out ]]; then
    print "✓ no Karabiner-Elements left on this Mac"
    exit 0
fi
exit 1
