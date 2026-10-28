#!/bin/bash
# One entry point for the S2 scripts. Run it as the admin user, never inside `sudo bash -c`:
#   bash ~/s2-scripts/run.sh <step> [<step> ...]
# It asks for the sudo password once, keeps sudo alive for all steps (no 5-minute timeout
# between them), runs each step as root with the right paths, logs each step to
# ~/s2-logs/<step>-<time>.log, keeps going after a failed step, and prints one summary.
# Steps: phases-2-4 phase-5 fan2go-build fan2go-config host-checks gpu-thermal accept-short accept-long mark-raid0-compute-only aide
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOGS="$HOME/s2-logs"; mkdir -p "$LOGS"
declare -A SCRIPT=(
  [phases-2-4]=provision-phases-2-4.sh [phase-5]=provision-phase-5.sh
  [fan2go-build]=provision-phase-6-fan2go-build.sh [fan2go-config]=provision-phase-6-fan2go-config.sh
  [host-checks]=host-checks.sh [gpu-thermal]=accept-gpu-thermal.sh
  [accept-short]=accept-short.sh [accept-long]=accept-long.sh
  [mark-raid0-compute-only]=mark-raid0-compute-only.sh [aide]=provision-aide.sh )
[ $# -ge 1 ] || { echo "usage: bash $0 <step> ...   steps: ${!SCRIPT[*]}"; exit 2; }
for s in "$@"; do [ -n "${SCRIPT[$s]:-}" ] && [ -f "$DIR/${SCRIPT[$s]}" ] || { echo "unknown step or missing script: $s"; exit 2; }; done
[ "$(id -u)" = 0 ] && { echo "Run as the admin user (not root, not inside sudo): bash $0 $*"; exit 2; }

echo "sudo password once for: $*"
sudo -v || exit 1
( while true; do sudo -n -v 2>/dev/null; sleep 50; done ) & KEEP=$!
trap 'kill $KEEP 2>/dev/null' EXIT

declare -a SUM=() RUNLOGS=()
for s in "$@"; do
  log="$LOGS/$s-$(date +%Y%m%d-%H%M).log"
  echo; echo "########## $s  ($(date '+%F %T'))  log: $log"
  sudo LOGDIR="$LOGS" bash "$DIR/${SCRIPT[$s]}" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}; RUNLOGS+=("$log")
  SUM+=("$(printf '%-14s %s  %s' "$s" "$([ $rc = 0 ] && echo OK || echo "FAILED (exit $rc)")" "$log")")
done
echo; echo "########## SUMMARY $(date '+%F %T')"; printf '%s\n' "${SUM[@]}"
# Failed checks of THIS call's host-checks run only (older logs would show fixed problems).
for l in "${RUNLOGS[@]:-}"; do case "$l" in *host-checks-*) grep '^FAIL' "$l" | sed 's/^/  host-checks: /';; esac; done | sort -u
