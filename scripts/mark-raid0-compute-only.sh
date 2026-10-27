#!/bin/bash
# options/raid0-compute-only.md: mark a RAID 0 machine as compute-only on purpose,
# so host-checks.sh expects RAID 0. Only for an agreed decision; record it in the fleet record.
set -euo pipefail
grep -E '^md' /proc/mdstat | grep -q raid0 || { echo "STOP: no RAID 0 array here"; exit 1; }
mkdir -p /etc/onprem-ai
echo "RAID 0 on purpose: compute-only node, no data that exists only here ($(date +%F))" > /etc/onprem-ai/raid0-compute-only
cat /etc/onprem-ai/raid0-compute-only
