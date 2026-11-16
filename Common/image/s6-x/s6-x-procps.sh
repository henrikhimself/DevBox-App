#!/usr/bin/env bash
# `sysctl --system` applies every key it can and only returns non-zero if any
# individual write fails. A single transient or kernel-unsupported key (e.g.
# package-shipped defaults under /usr/lib/sysctl.d) must not fail this oneshot,
# because a dependent service would otherwise never start. The important keys
# live in /etc/sysctl.conf and /etc/sysctl.d and are still applied;
# failures are logged.
#
# Runtime-specific ordering (for example Apple's swap-before-procps
# dependency) is added by the runtime hook /s6-x/s6-x-runtime.sh.
/s6-x/s6-add-run.sh procps 'oneshot' \
'/sbin/sysctl --system || printf "%s\n" "procps: sysctl --system reported a non-fatal error applying one or more keys; continuing" >&2'
