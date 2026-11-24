# Dropping Karabiner-Elements on c02 (the home Mac, an M2)

A handoff for the agent on c02. The owner wants to remove Karabiner-Elements from c02 if the
native replacement covers everything, and keep it if not. Their condition, in their words:
"it should continue opening the launchpad on m2".

## What Karabiner does on c02 today

`karabiner/karabiner.json` (exported from c02) holds the whole config:

- Caps Lock → Launchpad, on every keyboard (profile `simple_modifications`)
- SteelSeries Apex 3 TKL (vendor 4152, product 5666): Cmd ↔ Option, both sides
- F1–F12 as media keys (Karabiner's built-in `fn_function_keys` defaults), with F4 → Launchpad
  and F5 kept as F5
- `virtual_hid_keyboard.keyboard_type_v2 = iso`

No complex rules, no other devices.

## The native replacement (already working on c03, an M5 on macOS 27)

Import step 18 (`./import.sh --steps 18`) runs only where Karabiner is **not** installed:

- `macos/capslock-to-f18.zsh`: a login agent maps Caps Lock to F18 with `hidutil`, on all keyboards.
- `macos/modifier-keys.py`: writes the Apex's Cmd ↔ Option swaps and F-key media pairs into
  macOS's per-keyboard setting (`defaults -currentHost read -g com.apple.keyboard.modifiermapping.4152-5666-0`).
  macOS loads it when the keyboard connects. It maps Karabiner's `launchpad` target to F18.
  Tested by `macos/test-modifier-keys.zsh`.
- F18 opens Launchpad (Show Apps on macOS 27) only through keyboard shortcut 160. On c03 that is
  a per-machine keep (`machine-keeps.json` → `symbolic-hotkeys.c03.plist`: 160 on, key F18).
  **The shared record `macos/symbolic-hotkeys.plist`, which c02 uses, has 160 off with no key.**
  Without a change there, Caps Lock and F4 would send F18 on c02 and nothing would open.

On c03 the owner confirmed every key below works after a replug.

## Steps on c02

1. `git pull` in dev-env. Confirm this Mac is c02 (`zsh -c 'source ./machine-label.sh; echo $MACHINE_LABEL'`);
   the session that wrote this assumed the owner's "M2" is c02. Read `README.md` steps 13, 17, 18 and `machine-keeps.json`.
2. Check whether Launchpad exists: `ls -d /System/Applications/Launchpad.app /System/Applications/Apps.app`.
   Shortcut 160 is "Show Launchpad" before macOS 27 and "Show Apps" on 27; either way it is what
   Caps Lock and F4 must open.
3. Make shortcut 160 = F18 (on) apply on c02. Recommended: make it the shared value in
   `macos/symbolic-hotkeys.plist` (both Macs then agree) and drop c03's keep for `160` from
   `machine-keeps.json` and the 160 entry from `macos/symbolic-hotkeys.c03.plist`. Update the
   docstring in `macos/symbolic-hotkeys.py` that says the home Mac has it off. The F18 value is
   the one in `macos/symbolic-hotkeys.c03.plist` (parameters `65535, 79, 8388608`). Follow the
   repo's own record rules (`lib/sync_state.py`, export refusing a stale record).
4. Remove `cask "karabiner-elements"` from `Brewfile.personal`, so it is not reinstalled.
5. Commit and push those repo changes (the repo is public: no personal content).
6. The owner uninstalls Karabiner-Elements (`brew uninstall --cask karabiner-elements`; it asks
   for a password and may want a restart). Ask them to; do not run it yourself.
7. Run `./import.sh --steps 17,18`, answer yes to the shortcut, Caps Lock and keyboard-mapping
   prompts. Then `./import.sh --check --steps 17,18` must show ✓ for both.
8. The owner unplugs and replugs the Apex. If Keyboard Setup Assistant appears, the type is ISO
   (Karabiner's config said so). Then they check the list below.

| Key | Expected |
|---|---|
| Caps Lock (Apex and the laptop keyboard) | Launchpad / Show Apps opens |
| F1 / F2 | brightness down / up |
| F3 | Mission Control |
| F4 | Launchpad / Show Apps |
| F5 | plain F5 |
| F6 | Do Not Disturb on/off |
| F7 / F8 / F9 | previous / play-pause / next |
| F10 / F11 / F12 | mute / volume down / volume up |
| Apex Windows key / Alt key | Option / Command |

To read what the Apex actually has, use `ioreg -r -c IOHIDEventService -l` (its
`HIDEventServiceProperties`); `hidutil property --get HIDKeyboardModifierMappingPairs` prints
`(null)` even while the mapping is live. Expect 15 pairs: 4 swaps, 11 F keys.

## If something fails

Reinstall the cask (`brew install --cask karabiner-elements`) and run `./import.sh --steps 13`,
which copies `karabiner/karabiner.json` back. Report to the owner which key failed and what ioreg shows.

## Open decision for the owner, after it works

With no Mac running Karabiner, `export.sh` no longer refreshes `karabiner/karabiner.json`, yet
`modifier-keys.py` still reads it as the source of the mappings. Ask the owner whether to move the
mappings into a dev-env keyboard file of its own (devices, swaps, F-key table) and retire the
Karabiner folder, or keep `karabiner.json` as a hand-edited record. Do not decide it for them.

When the work is done, delete this file in the same commit that records the outcome in `README.md`.
