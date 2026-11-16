#!/usr/bin/env bash
# Docker host/engine preflight for devbox-docker. Read-only: never starts,
# reconfigures or switches a daemon, context or host policy; no resource is
# created. Rejects (never works around) unsupported configurations.
#
# Library use:   source preflight.sh; dv::check <build|launch>
# CLI use:       preflight.sh <build|launch>
#
#   build   native Linux amd64 host, pinned docker CLI, effective endpoint is
#           a local Unix socket, reachable daemon is linux/amd64, rootful, and
#           has no userns-remap, plus required host tools.
#   launch  everything in `build`, plus the host devices /dev/fuse and
#           /dev/net/tun.
#
# Environment (all optional):
#   DOCKER_CMD            must name a `docker` command (default: docker)
#   DOCKER_HOST/CONTEXT   honored exactly as the docker CLI honors them
#   DEVBOX_DEVICE_ROOT    test hook: prefix for /dev/* device checks
# After a successful check: DOCKERPF_CMD and DOCKERPF_ENDPOINT are set.

dv::fail() { printf '❌ %s\n' "$1" >&2; return 1; }

dv::resolve_cmd() {
  local cmd="${DOCKER_CMD:-docker}"
  if [[ "$(basename -- "${cmd}")" != 'docker' ]]; then
    dv::fail "DOCKER_CMD must name the 'docker' command. Got: ${cmd}" || return 1
  fi
  command -v "${cmd}" >/dev/null 2>&1 || { dv::fail "docker CLI not found: ${cmd}"; return 1; }
  DOCKERPF_CMD="${cmd}"
}

# Effective endpoint: DOCKER_HOST wins; otherwise the context selected by
# DOCKER_CONTEXT or the CLI's current context; otherwise the default socket.
dv::effective_endpoint() {
  local host
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    DOCKERPF_ENDPOINT="${DOCKER_HOST}"
    return 0
  fi
  if ! host="$("${DOCKERPF_CMD}" context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)"; then
    dv::fail 'cannot inspect the effective Docker context' || return 1
  fi
  DOCKERPF_ENDPOINT="${host:-unix:///var/run/docker.sock}"
}

dv::check() {
  local mode="${1:-build}" os arch info ostype darch sec dev tool
  local dev_root="${DEVBOX_DEVICE_ROOT:-}"
  case "${mode}" in build|launch) ;; *) dv::fail "unknown preflight mode: ${mode}"; return 1 ;; esac

  os="$(uname -s)"
  [[ "${os}" == 'Linux' ]] || { dv::fail "unsupported host OS '${os}'; devbox-docker requires native Linux."; return 1; }
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) ;;
    *) dv::fail "unsupported host architecture '${arch}'; devbox-docker requires native amd64 (no emulation)."; return 1 ;;
  esac

  for tool in jq curl tar sha256sum; do
    command -v "${tool}" >/dev/null 2>&1 || { dv::fail "required host tool not found: ${tool}"; return 1; }
  done

  dv::resolve_cmd || return 1
  dv::effective_endpoint || return 1
  case "${DOCKERPF_ENDPOINT}" in
    unix://*) ;;
    *) dv::fail "unsupported Docker endpoint '${DOCKERPF_ENDPOINT}'; only a local Unix socket is supported (no ssh/tcp/remote endpoints). Context and environment overrides are not switched."; return 1 ;;
  esac

  if ! info="$("${DOCKERPF_CMD}" info --format '{{.OSType}}|{{.Architecture}}|{{json .SecurityOptions}}' 2>&1)"; then
    dv::fail "cannot reach the Docker daemon at ${DOCKERPF_ENDPOINT}: ${info}"; return 1
  fi
  IFS='|' read -r ostype darch sec <<< "${info}"
  [[ "${ostype}" == 'linux' ]] || { dv::fail "daemon OSType '${ostype}' is not linux."; return 1; }
  case "${darch}" in
    x86_64|amd64) ;;
    *) dv::fail "daemon architecture '${darch}' is not amd64."; return 1 ;;
  esac
  if [[ "${sec}" == *'name=rootless'* ]]; then
    dv::fail 'the outer Docker Engine is rootless; a rootful Engine is required.'; return 1
  fi
  if [[ "${sec}" == *'name=userns'* ]]; then
    dv::fail 'the outer Docker Engine uses userns-remap; it must run without it.'; return 1
  fi

  if [[ "${mode}" == 'launch' ]]; then
    for dev in /dev/fuse /dev/net/tun; do
      [[ -c "${dev_root}${dev}" ]] || { dv::fail "host device ${dev} is missing."; return 1; }
    done
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -u
  dv::check "${1:-build}" || exit 1
fi
