#!/usr/bin/env bash
if [ -x /home/linuxbrew/.linuxbrew/bin/fnm ]; then
  fnm_env="$(/home/linuxbrew/.linuxbrew/bin/fnm env)"
  eval "${fnm_env}"
fi
