#!/usr/bin/env bash
# DevBox first-run installer: a thin interactive-login guard that runs the
# stdlib-only Python orchestrator at /usr/local/bin/devbox-install.
if [[ "$-" != *i* ]]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi
  exit 0
fi
python3 /usr/local/bin/devbox-install
