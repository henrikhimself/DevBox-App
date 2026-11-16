#!/usr/bin/env bash
# Runtime-neutral host helpers shared by the Apple Container and Docker
# frontends: name validation, option errors, confirmation, profile volume names
# and defaults. Sourced, never executed. Bash 3.2 compatible.

dv::require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '❌ jq is required to parse container inspect output.' >&2
    exit 1
  fi
}

dv::profile_name_from_container_name() {
  local container_name="${1}"
  local profile_name

  if [[ "${container_name}" != devbox-* ]]; then
    return 1
  fi

  profile_name="${container_name#devbox-}"
  profile_name="${profile_name%-keep}"
  printf '%s' "${profile_name}"
}

# Validates the character rule shared by all devbox names (profile names and
# tmux session names): must start with an alphanumeric character and contain
# only letters, numbers, or underscore. Hyphens are banned so the name never
# collides with the internal 'devbox-<profile>' / 'devbox-<profile>-keep'
# container naming. The character set is tmux-safe (no '.' or ':'), so the
# name is also valid inside the tmux session name devbox-<profile>[:<name>].
# $2 is the parameter label used in the error message (e.g. 'profile-name'
# or 'session-name'). Exits 1 on failure.
dv::validate_devbox_name() {
  local name="${1}"
  local label="${2:-name}"

  if ! [[ "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_]*$ ]]; then
    printf '%s\n' "❌ ${label} must start with an alphanumeric character, contain only letters, numbers, or underscore (hyphens are not allowed)." >&2
    exit 1
  fi
}

dv::validate_profile_name() {
  local name="${1}"

  # A profile name can no longer end in '-keep' (hyphens are banned), so the
  # kept-container naming rule needs no extra check here.
  dv::validate_devbox_name "${name}" 'profile-name'
}

dv::opt_error() {
  local opt="${1}"
  local optarg="${2}"
  local usage_fn="${3}"

  case "${opt}" in
    ':') printf '%s\n' "❌ Missing value for option: -${optarg}" >&2 ;;
    '?') printf '%s\n' "❌ Unknown option: -${optarg}" >&2 ;;
  esac
  "${usage_fn}"
  exit 1
}

# Prompts "<prompt> [y/N] "; returns 0 on yes (or assume_yes=1), else 1.
# Non-interactive without assume_yes returns 1.
dv::confirm() {
  local prompt="${1}"
  local assume_yes="${2}"
  local confirm_answer

  if [[ "${assume_yes}" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    printf '%s\n' '❌ Confirmation required. Re-run with -y for non-interactive use.' >&2
    return 1
  fi

  read -r -p "${prompt} [y/N] " confirm_answer
  case "${confirm_answer}" in
    y|Y|yes|YES|Yes)
      return 0
      ;;
    *)
      printf '%s\n' 'Cancelled.' >&2
      return 1
      ;;
  esac
}

dv::set_profile_volume_vars() {
  local name="${1}"

  # shellcheck disable=SC2034 # used by callers after this function returns
  HOME_VOLUME="devbox-${name}"
  # shellcheck disable=SC2034 # used by callers after this function returns
  DOCKER_VOLUME="devbox-${name}-docker"
}

dv::cpu_cores_default() {
  local total_cores
  local cores

  # Feature-detect the tool: nproc exists on Linux but not on macOS, so the
  # default depends on the host, not the runtime.
  if command -v nproc >/dev/null 2>&1; then
    total_cores="$(nproc)"
  elif command -v sysctl >/dev/null 2>&1; then
    total_cores="$(sysctl -n hw.ncpu)"
  else
    total_cores=1
  fi

  cores=$(( total_cores > 1 ? total_cores - 1 : 1 ))
  printf '%s' "${cores}"
}
