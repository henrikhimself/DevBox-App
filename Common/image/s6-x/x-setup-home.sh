#!/usr/bin/env bash
set -euo pipefail

mkdir -p /home/bob
chmod 755 /home/bob
cp -a -n /etc/skel/. /home/bob/
chown -R bob:bob /home/bob
