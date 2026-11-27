#!/bin/zsh
# Tests update-all's asdf pin bump from .zshrc.base against a made-up ~/.tool-versions and a stub
# asdf: every line is read intact while `asdf set` rewrites the file, and no pin moves down.
# Run: ./test-update-all-asdf-pins.zsh
emulate -L zsh

here=${0:A:h}
base=$here/.zshrc.base
fails=0

check() {  # check <label> <condition...>
  local label=$1; shift
  if "$@"; then print "ok   $label"; else print "FAIL $label"; fails=1; fi
}

for fn in _update-all-version-newer _update-all-bump-asdf-pins; do
  body=$(sed -n "/^$fn() {\$/,/^}\$/p" "$base")
  [[ -n $body ]] || { print -u2 "$fn not found in $base"; exit 1 }
  eval "$body"
done

tmp=$(mktemp -d)
trap 'command rm -rf -- "$tmp"' EXIT
HOME=$tmp

# golang's new pin is one byte shorter than the old one; python is offered an older release.
print -l 'golang 1.23.9' 'dotnet 10.0.400' 'python 3.12.16' 'nodejs 24.1.0' 'java system' > $tmp/.tool-versions
typeset -A newest=(golang 1.23.10 dotnet 10.0.999 python 3.12.0 nodejs 24.2.0)
_update-all-asdf-latest() { print -r -- $newest[$1] }
asked=$tmp/asked
asdf() {
  print -r -- "$*" >> $asked
  [[ $1 == set ]] || return 0
  local text=$(<$HOME/.tool-versions)
  # Rewrite in place, shortening the file, as a pin with fewer digits does.
  print -r -- "${text/(#m)$3 [^$'\n']##/$3 ${4%.*}}" > $HOME/.tool-versions
}
setopt extended_glob
out=$(_update-all-bump-asdf-pins)
rc=$?

called() { grep -qxF -- "$1" $asked }
not_asked_about() { ! grep -qF -- "$1" $asked }
refusal_reported() { [[ $out == *"Action needed:"*"3.12.0"*"python"*"3.12.16"* ]] }
check "the bump succeeds" test $rc -eq 0
check "golang moves up" called "install golang 1.23.10"
check "the line after a rewrite is read intact" called "install nodejs 24.2.0"
check "dotnet is left alone" not_asked_about otnet
check "no older release is installed" not_asked_about python
check "the refused downgrade is reported" refusal_reported

exit $fails
