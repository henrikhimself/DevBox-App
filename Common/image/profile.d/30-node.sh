#!/usr/bin/env bash
# 16-node-lts.py installs the pinned Node into fnm's FNM_DIR (fnm stores each
# version under <FNM_DIR>/node-versions/v<ver>/). An earlier profile step
# (20-fnm.sh) usually exposes it on PATH via `fnm env`; add the installed
# version here only when node is not already resolvable, so we never clobber
# that resolution.
if ! command -v node >/dev/null 2>&1; then
  fnm_dir="${FNM_DIR:-}"
  if [ -z "${fnm_dir}" ]; then
    fnm_dir="$(fnm dir 2>/dev/null)"
  fi
  if [ -n "${fnm_dir}" ] && [ -d "${fnm_dir}/node-versions" ]; then
    installed="$(ls -1d "${fnm_dir}"/node-versions/v[0-9]* 2>/dev/null | head -n1)"
    [ -n "${installed}" ] && export PATH="${PATH}:${installed}/bin"
  fi
fi
if [ -d "${HOME}/.local/node" ]; then
  export PATH="${PATH}:${HOME}/.local/node/node_modules/.bin"
fi

node_extra_ca_certs='/usr/local/share/ca-certificates/PersonalCA.crt'
if [ -x "${node_extra_ca_certs}" ]; then
  export NODE_EXTRA_CA_CERTS="${node_extra_ca_certs}"
fi
