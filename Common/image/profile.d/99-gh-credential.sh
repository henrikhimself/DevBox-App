#!/usr/bin/env sh
# shellcheck disable=SC2016,SC2310,SC2312,SC2317 # This profile is sourced indirectly; `pass` is an optional credential probe.

# Only run for interactive logins
case "$-" in
  *i*) ;;
  *) return 2>/dev/null; exit 0 ;;
esac

# Export GH_TOKEN from the pass store if the entry exists.
# This prevents gh from falling back to plaintext credential storage.
GH_PASS_ENTRY="gh/github.com"
if pass show "${GH_PASS_ENTRY}" >/dev/null 2>&1; then
  GH_TOKEN="$(pass show "${GH_PASS_ENTRY}")"
  export GH_TOKEN
fi
