#!/bin/zsh
# Tests update-all's mas stage helper (_update-all-mas-upgrade in .zshrc.base) against a fake mas:
# an App Store refusal is reported by name, recorded, left out of the next run, and retried once
# the app's version changes. Run: ./test-update-all-mas.zsh
# No err_return: the helper runs under update-all's plain `zsh -c`, where a failing mas call
# must not end it before the refusal is handled.
emulate -L zsh

here=${0:A:h}
fn=$(sed -n '/^_update-all-mas-upgrade() {$/,/^}$/p' "$here/.zshrc.base")
[[ -n $fn ]] || { print -u2 "_update-all-mas-upgrade not found in $here/.zshrc.base"; exit 1 }
eval "$fn"

tmp=$(mktemp -d)
trap 'command rm -rf -- "$tmp"' EXIT
export XDG_CACHE_HOME=$tmp
state=$tmp/update-all/mas-refused
fails=0

# Fake mas: `outdated` prints $OUTDATED; `upgrade` logs its ids, prints $UPGRADE_ERR to stderr,
# and fails when that is non-empty.
mas() {
  case $1 in
    outdated) [[ -n $OUTDATED ]] && print -r -- "$OUTDATED" ;;
    upgrade) shift; print -r -- "$*" >> "$tmp/upgraded"; [[ -z $UPGRADE_ERR ]] || { print -ru2 -- "$UPGRADE_ERR"; return 1 } ;;
  esac
}

check() {  # check <label> <condition...>
  local label=$1; shift
  if "$@"; then print "ok    $label"; else print "FAIL  $label"; fails=1; fi
}

run() { : >| "$tmp/upgraded"; out=$(_update-all-mas-upgrade 2>&1); rc=$? }

# 1: Pages refused, GarageBand updated
OUTDATED=$'682658836  GarageBand  (10.4.14 -> 10.4.15)\n361309726  Pages  (15.1.1 -> 16.0)'
UPGRADE_ERR='Error: No downloads initiated for ADAM ID 361309726'
run || true
check "refusal alone leaves the stage ok" test $rc -eq 0
check "both apps were tried" test "$(<$tmp/upgraded)" = "682658836 361309726"
check "the refusal is named, not shown as an ADAM ID error" eval '[[ $out == *"Action needed: the App Store will not update Pages through mas"* && $out != *"ADAM ID"* ]]'
check "the refusal is recorded with its versions" test "$(<$state)" = $'361309726\t15.1.1 16.0'

# 2: next run, same versions: Pages is held, mas is not asked, the action line repeats
OUTDATED='361309726  Pages  (15.1.1 -> 16.0)'
UPGRADE_ERR=''
run || true
check "a held app is not sent to mas" test ! -s "$tmp/upgraded"
check "a held app is still named" eval '[[ $out == *"will not update Pages"* ]]'
check "the hold stays recorded" test "$(<$state)" = $'361309726\t15.1.1 16.0'

# 3: a newer release arrives: Pages is tried again, and succeeds
OUTDATED='361309726  Pages  (15.1.1 -> 16.1)'
run || true
check "a changed version is tried again" test "$(<$tmp/upgraded)" = "361309726"
check "a success clears the record" test ! -s "$state"
check "no action line after a success" eval '[[ $out != *"Action needed"* ]]'

# 4: any other error still fails the stage and is shown
OUTDATED='361285480  Keynote  (15.1.1 -> 16.0)'
UPGRADE_ERR='Error: Download failed'
run || true
check "another error fails the stage" test $rc -ne 0
check "another error is shown" eval '[[ $out == *"Error: Download failed"* ]]'

# 5: nothing outdated
OUTDATED=''
UPGRADE_ERR=''
print -r -- $'361309726\t15.1.1 16.0' >| "$state"
run || true
check "nothing outdated says so" eval '[[ $out == "mas: nothing to upgrade" ]]'
check "nothing outdated sends nothing to mas" test ! -s "$tmp/upgraded"

exit $fails
