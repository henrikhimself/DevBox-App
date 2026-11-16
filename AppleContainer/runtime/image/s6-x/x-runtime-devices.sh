#!/usr/bin/env bash
# Apple Container guest: create the TUN and FUSE device nodes inside the VM.
mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
mknod /dev/fuse c 10 229 && chmod 666 /dev/fuse
chown bob:bob /dev/net/tun /dev/fuse
exit 0
