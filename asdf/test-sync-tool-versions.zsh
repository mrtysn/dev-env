#!/bin/zsh
# Test sync-tool-versions.py on files in a sandbox, with a stub asdf that records what it is asked
# to do: the real ~/.tool-versions and asdf are never touched.
set -u -o pipefail
here=${0:A:h}
tool=$here/sync-tool-versions.py
tmp=${$(mktemp -d):A}
trap 'rm -rf -- "$tmp"' EXIT
export DEV_ENV_STATE_DIR=$tmp/state DEV_ENV_KEEPS=$tmp/keeps.json ASDF=$tmp/asdf
print -r -- '{"c03": {"asdf/tool-versions": ["java"]}}' > $DEV_ENV_KEEPS
print -r -- '#!/bin/zsh
print -r -- "$*" >> '$tmp'/asdf.log
[[ "$*" == "install nodejs 99.0.0" ]] && exit 1
[[ $1 == plugin && $2 == list ]] && print -l nodejs python pnpm
exit 0' > $ASDF; chmod +x $ASDF
rec=$tmp/record; mkdir -p $rec
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); print -r -- "FAIL: $1"; }
plain() { sed $'s/\x1b\\[[0-9;]*m//g'; }
t() { local m=$1 live=$2; shift 2; $tool "$@" --label $m --live $live --record $rec | plain; }

print -l "nodejs 24.22.3" "python 3.12.16" "pnpm 12.21.0" "java system" > $rec/tool-versions

# This Mac is newer on pnpm: check and import leave it, export raises the repo.
print -l "nodejs 24.22.3" "python 3.12.16" "pnpm 12.23.0" "java system" > $tmp/c02
t c02 $tmp/c02 check >/dev/null && ok || bad "check reports a downgrade as a difference"
[[ $(t c02 $tmp/c02 import) == *"at or above"* && ! -e $tmp/asdf.log ]] && ok || bad "import acted on a newer Mac"
out=$(t c02 $tmp/c02 export)
[[ $out == *"pnpm 12.21.0 -> 12.23.0"* && $(grep pnpm $rec/tool-versions) == "pnpm 12.23.0" ]] && ok || bad "export did not raise pnpm: $out"
[[ $(t c02 $tmp/c02 export) == *"at or above this Mac's"* ]] && ok || bad "second export wrote something"

# A Mac that is behind on one tool and lacks another: import upgrades and adds, never lowers.
print -l "nodejs 24.30.0" "python 3.12.10" > $tmp/c04
out=$(t c04 $tmp/c04 check)
[[ $out == *"python 3.12.10 -> 3.12.16"* && $out == *"pnpm (not pinned) -> 12.23.0"* && $out != *nodejs* ]] && ok || bad "check plan: $out"
out=$(t c04 $tmp/c04 import)
[[ $(grep python $tmp/c04) == "python 3.12.16" && $(grep nodejs $tmp/c04) == "nodejs 24.30.0" && $(grep java $tmp/c04) == "java system" ]] && ok || bad "import result: $(cat $tmp/c04)"
[[ $(<$tmp/asdf.log) == *"install python 3.12.16"* && $(<$tmp/asdf.log) == *"plugin add java"* && $(<$tmp/asdf.log) != *"install java"* ]] && ok || bad "asdf calls: $(<$tmp/asdf.log)"
ls $tmp/c04.backup-* >/dev/null 2>&1 && ok || bad "import kept no backup"
# Export from that Mac raises nodejs only, and lowers nothing.
t c04 $tmp/c04 export >/dev/null
[[ $(grep nodejs $rec/tool-versions) == "nodejs 24.30.0" && $(grep pnpm $rec/tool-versions) == "pnpm 12.23.0" ]] && ok || bad "c04 export: $(cat $rec/tool-versions)"

# A failed install leaves that pin where it was and reports it.
print -l "nodejs 99.0.0" >> $rec/tool-versions.tmp; sed -i '' 's/^nodejs .*/nodejs 99.0.0/' $rec/tool-versions; rm -f -- $rec/tool-versions.tmp
out=$(t c04 $tmp/c04 import); rc=$?
[[ $rc != 0 && $out == *"nodejs 99.0.0 failed to install"* && $(grep nodejs $tmp/c04) == "nodejs 24.30.0" ]] && ok || bad "failed install: rc=$rc $out"
sed -i '' 's/^nodejs .*/nodejs 24.30.0/' $rec/tool-versions

# A kept tool: c03 keeps its own java, exactly, and its export leaves the shared java alone.
print -l "nodejs 24.30.0" "python 3.12.16" "pnpm 12.23.0" "java openjdk-17" > $tmp/c03
t c03 $tmp/c03 export >/dev/null
[[ $(<$rec/tool-versions.c03) == "java openjdk-17" && $(grep java $rec/tool-versions) == "java system" ]] && ok || bad "kept java: $(cat $rec/tool-versions.c03 2>&1)"
t c03 $tmp/c03 check >/dev/null && ok || bad "c03 differs from its kept java"
t c02 $tmp/c02 check | grep -q java && bad "c03's java reached c02" || ok

# --allow-downgrade moves a pin down to the repo's.
sed -i '' 's/^pnpm .*/pnpm 12.0.0/' $rec/tool-versions
t c02 $tmp/c02 check | grep -q pnpm && bad "a lower repo pin counts without --allow-downgrade" || ok
[[ $(t c02 $tmp/c02 check --allow-downgrade) == *"pnpm 12.23.0 -> 12.0.0"* ]] && ok || bad "--allow-downgrade does not offer the lower pin"

print "sync-tool-versions: $pass passed, $fail failed"
(( fail == 0 ))
