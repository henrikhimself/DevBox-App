#!/usr/bin/env bash
# Base PATH setup: deduplicate PATH, then place ${HOME}/bin (first)
# and ${HOME}/.local/bin at the front, in that order.

# Only run for interactive logins
if [[ "$-" != *i* ]]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  fi
  exit 0
fi

firstrun_marker="${HOME}/.devbox-profile"
if [[ -f "${firstrun_marker}" ]]; then
  return 0
fi

cat >> /home/bob/.profile <<'EOF'

export LANG=C.UTF-8

# Step 1: Deduplicate existing PATH entries (first occurrence wins).
base_env_path=""
IFS=':'
for base_env_dir in ${PATH}; do
  [ -n "${base_env_dir}" ] || continue
  case ":${base_env_path}:" in
    *":${base_env_dir}:"*) ;;
    *) base_env_path="${base_env_path}:${base_env_dir}" ;;
  esac
done
unset IFS
# Step 2: Drop the two target dirs from their current position (if any) so they
# can be placed at the front in a deterministic order.
base_env_rest=""
IFS=':'
for base_env_dir in ${base_env_path}; do
  [ -n "${base_env_dir}" ] || continue
  if [ "${base_env_dir}" = "${HOME}/bin" ] || [ "${base_env_dir}" = "${HOME}/.local/bin" ]; then
    continue
  fi
  base_env_rest="${base_env_rest}:${base_env_dir}"
done
unset IFS
# Step 3: Final PATH layout: ~/bin first, then ~/.local/bin, then the rest.
PATH="${HOME}/bin:${HOME}/.local/bin${base_env_rest}"
export PATH
unset base_env_path base_env_rest base_env_dir
EOF
touch "${firstrun_marker}"
