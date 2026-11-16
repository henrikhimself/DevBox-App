#!/usr/bin/env bash
if [ -d "${HOME}/.pi/agent/npm/node_modules/.bin" ]; then
  export PATH="${PATH}:${HOME}/.pi/agent/npm/node_modules/.bin"
fi
