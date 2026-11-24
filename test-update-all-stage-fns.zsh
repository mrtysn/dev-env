#!/bin/zsh
# Tests the function list update-all copies into its stage subshells (stage_fns in .zshrc.base):
# every name in it is defined in .zshrc.base, and update-all refuses to start any stage when one
# is not. A typo there (two names run together) once made every stage fail with exit 127.
# Run: ./test-update-all-stage-fns.zsh
emulate -L zsh

here=${0:A:h}
base=$here/.zshrc.base
fails=0

check() {  # check <label> <condition...>
  local label=$1; shift
  if "$@"; then print "ok   $label"; else print "FAIL $label"; fails=1; fi
}

# 1. Static: each required name has a `name() {` definition in .zshrc.base.
block=$(sed -n '/^  local -a stage_fns=($/,/^  )$/p' "$base")
[[ -n $block ]] || { print -u2 "stage_fns list not found in $base"; exit 1 }
names=(${=${${block#*\(}%\)}})
check "stage_fns lists names" test ${#names} -gt 0
for n in $names; do
  check "$n is defined" grep -q "^$n() *{" "$base"
done

# 2. Runtime: with none of the stage functions defined, update-all stops before any stage.
fn=$(sed -n '/^update-all() {$/,/^}$/p' "$base")
[[ -n $fn ]] || { print -u2 "update-all not found in $base"; exit 1 }
tmp=$(mktemp -d)
trap 'command rm -rf -- "$tmp"' EXIT
out=$(HOME=$tmp zsh -fc '
  script() { print stage-started; }
  softwareupdate() { :; }
  sudo() { return 1; }
  eval "$1"; update-all' _ "$fn" 2>&1)
rc=$?
check "update-all fails when stage functions are missing" test $rc -eq 1
names_missing() { [[ $out == *"not defined"*_update-all-stage* ]] }
no_stage_ran() { [[ $out != *stage-started* ]] }
check "the error names the missing function" names_missing
check "no stage runs" no_stage_ran

exit $fails
