#!/usr/bin/env bash
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  brew_env="$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  eval "${brew_env}"
fi
