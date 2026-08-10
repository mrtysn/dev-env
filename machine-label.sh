# Single source of truth for the machine → label mapping.
#   c01 = Office     c02 = Home
# Sourced by export.sh and import.sh; the label names every per-machine file:
# .zshrc.<label>, Brewfile.<label>, tmux/<label>.conf, asdf/tool-versions.<label>.
#
# LocalHostName, not `hostname -s`: the latter can resolve to a DHCP name
# (e.g. "192") on some LANs and misroute per-machine files.
#
# Known exception: the ~/.zshrc loader (shipped by import.sh, exported back as
# .zshrc.loader) carries its own copy of this mapping — shell startup must not
# depend on this repo, whose path differs per machine.
# One case per machine: add a LocalHostName here to bind it to a label.
case "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" in
    mrtysn-mbp-m2max)  MACHINE_LABEL="c02"; MACHINE_NAME="C02 (Home)" ;;
    *)                 MACHINE_LABEL="";   MACHINE_NAME="unknown" ;;
esac
