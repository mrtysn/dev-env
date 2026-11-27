#!/bin/zsh
# Tests how update-all handles a stage that stops to ask something (functions in .zshrc.base):
# the question is on screen and in the log while the command still waits, it is recognised for the
# notification, and brew's Ctrl-C and missing-app outcomes are read through `script`.
# brew is a made-up function or program; nothing is upgraded and no notification is sent.
# Run: ./test-update-all-prompts.zsh
emulate -L zsh
setopt extended_glob

here=${0:A:h}
base=$here/.zshrc.base
fails=0

check() {  # check <label> <condition...>
  local label=$1; shift
  if "$@"; then print "ok   $label"; else print "FAIL $label"; fails=1; fi
}

brew_fns=(_update-all-brew-upgrade _update-all-brew-run _update-all-brew-same-version-casks)
for fn in _update-all-pending-question _update-all-ask-skip $brew_fns; do
  body=$(sed -n "/^$fn() {\$/,/^}\$/p" "$base")
  [[ -n $body ]] || { print -u2 "$fn not found in $base"; exit 1 }
  eval "$body"
done

tmp=$(mktemp -d)
trap 'command rm -rf -- "$tmp"' EXIT
log=$tmp/stage.log

asks() { print -rn -- "$1" > $log; _update-all-pending-question $log >/dev/null }
quiet() { ! asks "$1" }
check "a licence question is recognised" asks $'text\r\nDo you accept the license terms? (Enter YES or NO)\r\n'
check "a y/n question is recognised" asks $'\e[1mProceed? [y/N]\e[0m '
check "a password prompt is recognised" asks $'==> Installing\r\nPassword:'
check "ordinary output is not a question" quiet $'==> Pouring foo\r\n'
check "an answered question is not pending" quiet $'(Enter YES or NO)\r\nYES\r\n==> Pouring foo\r\n'

check "no terminal means quit, not skip" eval '! _update-all-ask-skip brew </dev/null'

# A made-up brew on PATH, run through the real `script`: it asks, and records whether the
# question had reached the log before it was answered.
mkdir $tmp/bin
cat > $tmp/bin/brew <<'EOF'
#!/bin/zsh
case $FAKE_BREW in
  held|only-held)
    if [[ $1 == outdated ]]; then
      row() { print -rn -- "{\"name\":\"$1\",\"installed_versions\":[\"$2\"],\"current_version\":\"$3\",\"pinned\":$4}" }
      print -n '{"casks":['; row loops 1.0,abc 1.0,abc false
      [[ $FAKE_BREW == held ]] && { print -n ,; row newer 1.0 2.0 false; print -n ,; row stuck 1.0 2.0 true }
      print ']}'
    else print "args: $*"; fi
    exit 0 ;;
  ask) [[ -t 1 ]] && print "stdout is a terminal"; print "args: $*"; exit 0 ;;
  interrupt) exit 130 ;;
  signal) kill -INT $$ ; sleep 5 ;;
  missing)
    [[ $1 == reinstall ]] && { print "reinstalled $3"; : > $FAKE_DONE; exit 0 }
    [[ -f $FAKE_DONE ]] && exit 0
    print $'\e[31mError\e[0m: someapp: It seems the App source \'/Applications/X.app\' is not there.'
    exit 1 ;;
esac
EOF
chmod +x $tmp/bin/brew
run() { FAKE_BREW=$1 FAKE_DONE=$tmp/done PATH=$tmp/bin:$PATH zsh -fc "$(typeset -f $brew_fns); _update-all-brew-upgrade" </dev/null 2>&1 }

out=$(run ask)
check "brew writes to a terminal" eval '[[ $out == *"stdout is a terminal"* ]]'
check "brew is not asked to confirm" eval '[[ $out == *"args: upgrade --no-ask"* ]]'
run interrupt >/dev/null; check "Ctrl-C exit 130 returns 130" test $? -eq 130
run signal >/dev/null;    check "death by SIGINT returns 130" test $? -eq 130
out=$(run missing); rc=$?
check "a missing app is reinstalled" eval '[[ $out == *"reinstalled someapp"* ]]'
check "and the retried upgrade succeeds" test $rc -eq 0
out=$(run held)
check "a cask at the offered version is named as held" eval '[[ $out == *"held back"*loops* ]]'
check "formulae are still upgraded" eval '[[ $out == *"args: upgrade --no-ask --formula"* ]]'
check "only the other unpinned casks are upgraded" eval '[[ $out == *"args: upgrade --no-ask --cask newer"[[:space:]]# ]]'
out=$(run only-held)
check "with only held casks, no cask upgrade runs" eval '[[ $out != *"--cask"* ]]'

exit $fails
