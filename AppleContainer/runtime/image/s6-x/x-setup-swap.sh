#!/usr/bin/env bash
set -euo pipefail

mkdir -p /swap

if grep -qsE '^/swap/swapfile[[:space:]]' /proc/swaps; then
  exit 0
fi

if [[ ! -f /swap/swapfile ]]; then
  mem_kb=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
  swap_kb=$((mem_kb * 2))

  fallocate -l "${swap_kb}K" /swap/swapfile
  chmod 600 /swap/swapfile
  mkswap /swap/swapfile
fi

chmod 600 /swap/swapfile
swapon /swap/swapfile
