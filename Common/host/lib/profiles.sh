#!/usr/bin/env bash
# Profile and port policy shared by all frontends. These functions decide *what*
# to do from runtime facts; the facts themselves come from the runtime adapter
# (dv::container_status, dv::container_ssh_host_port, dv::volume_exists,
# dv::all_volume_names, dv::all_devbox_names, dv::running_devbox_names).
# Sourced, never executed. Bash 3.2 compatible.

# Print the name of a devbox-* container (other than $2) whose configured
# SSH host port matches $1, if any exists among containers in the given
# state. $3 selects the container-name source: 'running' or 'all'.
# Returns 1 (prints nothing) if no conflict is found.
dv::find_port_conflict() {
  local port="${1}"
  local exclude_name="${2}"
  local scope="${3}"
  local candidates
  local name
  local other_port

  case "${scope}" in
    running) candidates="$(dv::running_devbox_names)" ;;
    all)     candidates="$(dv::all_devbox_names)" ;;
  esac

  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "${exclude_name}" ]] && continue
    other_port="$(dv::container_ssh_host_port "${name}")"
    if [[ -n "${other_port}" && "${other_port}" == "${port}" ]]; then
      printf '%s' "${name}"
      return 0
    fi
  done <<< "${candidates}"

  return 1
}

# Finds a free host port in [pool_start, pool_end] for a new devbox container,
# skipping ports already used by any devbox-* container (scope 'all'). $3
# excludes the not-yet-created container. Exits 1 if the whole pool is taken.
dv::allocate_pool_port() {
  local pool_start="${1}"
  local pool_end="${2}"
  local exclude_name="${3}"
  local -a used_ports
  local name
  local candidate_port
  local port
  local all_names

  # Enumerate devbox ports once into an in-memory set, then scan the pool
  # against it. This avoids both:
  #   1) re-inspecting containers for each candidate port, and
  #   2) spawning an external membership-check process per candidate port.
  used_ports=()
  all_names="$(dv::all_devbox_names)"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "${exclude_name}" ]] && continue
    candidate_port="$(dv::container_ssh_host_port "${name}")"
    if [[ "${candidate_port}" =~ ^[0-9]+$ ]]; then
      used_ports[candidate_port]=1
    fi
  done <<< "${all_names}"

  for (( port = pool_start; port <= pool_end; port++ )); do
    if [[ -z "${used_ports[port]+x}" ]]; then
      printf '%s' "${port}"
      return 0
    fi
  done

  printf '%s\n' "❌ No available SSH host port in the pool ${pool_start}-${pool_end} (all in use by existing devbox profiles). Use -p to choose a port outside the pool." >&2
  exit 1
}

# Newline-separated, sorted, deduplicated names of every created devbox
# profile. A profile counts as created when its init.sh volume pair exists
# (both devbox-<profile> and devbox-<profile>-docker) or a devbox-<profile>
# container exists. The volume pair is authoritative - init.sh creates both,
# run.sh requires both, discard.sh deletes both (so a discarded profile
# disappears from this list), and an ephemeral container's auto-removal
# (--rm) leaves the pair intact. Requiring both volumes also disambiguates a
# legacy 'devbox-a-b' volume between profile 'a-b's home volume and profile
# a's docker volume: only the reading with a complete pair counts. The
# container scan is a defensive backstop for pairs deleted out-of-band.
dv::all_profile_names() {
  local volumes
  local volume
  local base
  local volume_candidates
  local container_candidates
  local profile_name
  local name

  # Volume-derived candidates: for each devbox-* volume, the profile it names
  # directly, plus (for '-docker'-suffixed volumes) the profile whose docker
  # volume it is. A candidate only counts when both volumes of its own pair
  # exist, which also filters candidates produced by the -docker suffix
  # stripping of a volume whose owner is the longer name (e.g. 'a-docker'
  # from 'devbox-a-docker' when only profile 'a' exists).
  volume_candidates=''
  volumes="$(dv::all_volume_names)"
  while IFS= read -r volume; do
    if [[ "${volume}" == devbox-* ]]; then
      base="${volume#devbox-}"
      volume_candidates+="${base}"$'\n'
      if [[ "${base}" == *-docker ]]; then
        volume_candidates+="${base%-docker}"$'\n'
      fi
    fi
  done <<< "${volumes}"

  local volume_profiles
  volume_profiles="$(printf '%s' "${volume_candidates}" | grep -v '^[[:space:]]*$' | sort -u | while IFS= read -r profile_name; do
    if [[ "$(dv::volume_exists "devbox-${profile_name}")" == '1' && "$(dv::volume_exists "devbox-${profile_name}-docker")" == '1' ]]; then
      printf '%s\n' "${profile_name}"
    fi
  done || true)"

  # Container-derived candidates: always accepted - a devbox-* container is
  # proof of a created profile even if its volumes were deleted out-of-band.
  local all_names
  all_names="$(dv::all_devbox_names)"
  container_candidates=''
  while IFS= read -r name; do
    if [[ -n "${name}" ]]; then
      container_candidates+="$(dv::profile_name_from_container_name "${name}")"$'\n'
    fi
  done <<< "${all_names}"

  printf '%s\n%s\n' "${volume_profiles}" "${container_candidates}" | grep -v '^[[:space:]]*$' | sort -u || true
}

# Resolves which running devbox to act on from an optional profile name ($1,
# '' if -v absent). Sets globals PROFILE_NAME and CONTAINER_NAME. Exits 1 with
# a clear message if none match the profile, none run at all, or multiple run
# without -v.
dv::resolve_running_devbox() {
  local requested_profile="${1}"

  if [[ -n "${requested_profile}" ]]; then
    dv::validate_profile_name "${requested_profile}"

    CONTAINER_NAME=''
    local candidate
    local candidate_status
    for candidate in "devbox-${requested_profile}" "devbox-${requested_profile}-keep"; do
      candidate_status="$(dv::container_status "${candidate}")"
      if [[ "${candidate_status}" == 'running' ]]; then
        CONTAINER_NAME="${candidate}"
        break
      fi
    done

    if [[ -z "${CONTAINER_NAME}" ]]; then
      printf '%s\n' "❌ No running devbox for profile '${requested_profile}'." >&2
      exit 1
    fi

    # shellcheck disable=SC2034 # used by callers after this function returns
    PROFILE_NAME="${requested_profile}"
    return 0
  fi

  local running_names
  running_names="$(dv::running_devbox_names)"

  if [[ -z "${running_names}" ]]; then
    printf '%s\n' '❌ No devbox containers are running.' >&2
    exit 1
  fi

  local running_count=0
  local running_profiles=()
  local name
  local profile
  while IFS= read -r name; do
    [[ -z "${name}" ]] && continue
    running_count=$(( running_count + 1 ))
    CONTAINER_NAME="${name}"
    profile="$(dv::profile_name_from_container_name "${name}")"
    running_profiles+=("${profile}")
  done <<< "${running_names}"

  if [[ "${running_count}" -ne 1 ]]; then
    local profile_list
    profile_list="$(IFS=', '; printf '%s' "${running_profiles[*]}")"
    printf '%s\n' "❌ Multiple devbox containers found: ${profile_list}. Must use -v to pick one." >&2
    exit 1
  fi

  # shellcheck disable=SC2034 # used by callers after this function returns
  PROFILE_NAME="$(dv::profile_name_from_container_name "${CONTAINER_NAME}")"
}
