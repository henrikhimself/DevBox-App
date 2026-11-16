#!/usr/bin/env bash
# testenv.sh — Self-contained cross-platform test environment shim.
#
# Source this at the top of each test script. It detects the Apple Container
# command independently (no dependency on shared.sh or any other repository
# implementation file) and provides dv:: wrapper functions for test setup
# and teardown so that test scripts contain no direct container CLI calls.
#
# Usage in a test script:
#   source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"
#
# If your test needs a workspace path, call dv::make_tmpdir once (before
# referencing TENV_TMPDIR) to create it, and call cleanup_tmpdir from
# your dv::cleanup trap to remove it on exit.

# ── Runtime selection ────────────────────────────────────────────────────────
#
# The leaf runner of each frontend (AppleContainer/tests/run-tests.sh,
# Docker/tests/run-tests.sh) exports:
#   DEVBOX_TEST_RUNTIME   apple | docker
#   DEVBOX_FRONTEND_DIR   absolute path of the frontend under test
# Scripts under test are always invoked from that directory by path. There is
# no default: running a feature script directly without them is an error, so a
# test can never silently exercise the wrong runtime.

: "${DEVBOX_TEST_RUNTIME:?DEVBOX_TEST_RUNTIME not set; run through AppleContainer/tests/run-tests.sh or Docker/tests/run-tests.sh}"
: "${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through AppleContainer/tests/run-tests.sh or Docker/tests/run-tests.sh}"
# shellcheck disable=SC2034 # read by the feature scripts that source this file
TENV_FRONTEND_DIR="${DEVBOX_FRONTEND_DIR}"
TENV_FEATURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${DEVBOX_TEST_RUNTIME}" in
  apple|docker) ;;
  *) printf 'unknown DEVBOX_TEST_RUNTIME: %s\n' "${DEVBOX_TEST_RUNTIME}" >&2; exit 1 ;;
esac
# shellcheck source=backend-apple.sh
source "${TENV_FEATURES_DIR}/backend-${DEVBOX_TEST_RUNTIME}.sh"

# Runtime-neutral applicability: returns 0 when the runtime under test is $1.
dv::runtime_is() { [[ "${DEVBOX_TEST_RUNTIME}" == "${1}" ]]; }

# ── Temporary workspace directory ────────────────────────────────────────────
# Safe to use as a workspace path on both Linux and macOS (avoids SIP-protected
# paths such as /workspace that cannot be bind-mounted on macOS).
# /tmp is used as the base so that cleanup_tmpdir can guard the rm -rf
# by verifying the path is under /tmp. Both the created path and /tmp are
# canonicalized via 'cd ... && pwd -P' so that symlinks (e.g. macOS
# /tmp -> /private/tmp) do not defeat the check.
#
# Created lazily: only tests that actually need a workspace path should call
# dv::make_tmpdir (before referencing TENV_TMPDIR). Tests that never call it
# leave TENV_TMPDIR unset, and cleanup_tmpdir becomes a safe no-op for
# them, so no stray /tmp/devboxtest-* directories accumulate.

# Create TENV_TMPDIR. Call this once, before referencing TENV_TMPDIR, from any
# test that needs a workspace path.
dv::make_tmpdir() {
  local tmp_raw
  tmp_raw="$(mktemp -d /tmp/devboxtest-XXXXXX)"
  TENV_TMPDIR="$(cd "${tmp_raw}" && pwd -P)"
}

# Remove TENV_TMPDIR only when it is confirmed to be a subdirectory of /tmp
# (using canonical paths to resolve symlinks such as macOS /tmp -> /private/tmp).
# Safe no-op if dv::make_tmpdir was never called. Prints a warning and skips
# the removal if a non-empty TENV_TMPDIR fails the /tmp guard.
dv::cleanup_tmpdir() {
  if [[ -z "${TENV_TMPDIR:-}" ]]; then
    return 0
  fi

  local tmp_canonical
  tmp_canonical="$(cd /tmp 2>/dev/null && pwd -P)"
  if [[ "${TENV_TMPDIR}" == "${tmp_canonical}/"* ]]; then
    rm -rf "${TENV_TMPDIR}"
  else
    printf 'dv::cleanup_tmpdir: skipping rm -rf — %s is not under /tmp\n' \
      "${TENV_TMPDIR}" >&2
  fi
}

# Create TENV_FAKE_HOME, a scratch directory for tests to pass as an
# overridden HOME (e.g. `HOME="${TENV_FAKE_HOME}" bash ./code.sh ...`) so a
# script under test that writes to "${HOME}/.ssh/..." can never touch the
# real developer's actual ~/.ssh. Call this once, before referencing
# TENV_FAKE_HOME, from any test that invokes a HOME-writing script.
dv::make_fake_home() {
  local tmp_raw
  tmp_raw="$(mktemp -d /tmp/devboxtest-home-XXXXXX)"
  TENV_FAKE_HOME="$(cd "${tmp_raw}" && pwd -P)"
}

# Remove TENV_FAKE_HOME only when confirmed to be under /tmp (same guard
# pattern as cleanup_tmpdir). Safe no-op if never created.
dv::cleanup_fake_home() {
  if [[ -z "${TENV_FAKE_HOME:-}" ]]; then
    return 0
  fi

  local tmp_canonical
  tmp_canonical="$(cd /tmp 2>/dev/null && pwd -P)"
  if [[ "${TENV_FAKE_HOME}" == "${tmp_canonical}/"* ]]; then
    rm -rf "${TENV_FAKE_HOME}"
  else
    printf 'dv::cleanup_fake_home: skipping rm -rf — %s is not under /tmp\n' \
      "${TENV_FAKE_HOME}" >&2
  fi
}

# ── dv:: helpers ───────────────────────────────────────────────────────────

# Print an ephemeral, currently-unused TCP port number. Used by tests that
# need to publish a container port without risking collisions with a fixed
# port number that may already be bound on the host.
dv::free_port() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
  else
    # Fallback when python3 is unavailable: pick a random high port. Small
    # collision risk, but avoids a hard dependency on python3.
    printf '%s' "$(( (RANDOM % 20000) + 30000 ))"
  fi
}


# ── Stub runtime for argv-capturing tests ────────────────────────────────────
#
# dv::install_run_stub <dir>
# Writes an executable named after the selected runtime's CLI ('container' or
# 'docker') into <dir>. It logs every invocation (one line of "$*") to
# ${FAKE_CONTAINER_LOG} and mimics just enough of that CLI for run.sh/init.sh:
# backend/engine checks pass, no container exists, volumes/images exist,
# lifecycle verbs succeed. Put <dir> first on PATH when invoking the scripts.
#
# Docker only: the frontend runs its host/engine preflight against this stub.
# On a real Linux amd64 host that passes unmodified. For development
# self-checks on any other host set DEVBOX_TEST_FAKE_HOST=1: a fake `uname`
# (Linux/x86_64) is installed and DEVBOX_DEVICE_ROOT points at a fake /dev tree.
# That mode never replaces a real-runtime result.
dv::install_run_stub() {
  local dir="${1}"

  mkdir -p "${dir}"
  if [[ "${DEVBOX_TEST_RUNTIME}" == 'apple' ]]; then
    cat > "${dir}/container" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_CONTAINER_LOG:?}"
printf '%s\n' "$*" >> "${log_file}"

case "${1:-}" in
  system)  printf 'status running\n' ;;
  info)    exit 0 ;;
  inspect) exit 1 ;;
  list)    printf '[]\n' ;;
  volume)
    case "${2:-}" in
      inspect|create|rm) exit 0 ;;
    esac
    ;;
  image)
    case "${2:-}" in
      inspect|rm) exit 0 ;;
    esac
    ;;
  run|exec|start|stop|delete) exit 0 ;;
esac

exit 0
STUB
    chmod 755 "${dir}/container"
    return 0
  fi

  cat > "${dir}/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_CONTAINER_LOG:?}"
printf '%s\n' "$*" >> "${log_file}"

case "${1:-}" in
  context) printf 'unix:///var/run/docker.sock\n' ;;
  info)    printf 'linux|x86_64|["name=seccomp,profile=builtin","name=apparmor"]\n' ;;
  container)
    case "${2:-}" in
      inspect) exit 1 ;;
      ls)      exit 0 ;;
      run|start|stop|rm|create) exit 0 ;;
    esac
    ;;
  volume)
    case "${2:-}" in
      inspect|create|rm) exit 0 ;;
      ls) exit 0 ;;
    esac
    ;;
  image)
    case "${2:-}" in
      inspect|ls|rm) exit 0 ;;
    esac
    ;;
  exec) exit 0 ;;
esac

exit 0
STUB
  chmod 755 "${dir}/docker"

  if [[ "${DEVBOX_TEST_FAKE_HOST:-0}" == '1' ]]; then
    cat > "${dir}/uname" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in -m) echo x86_64 ;; *) echo Linux ;; esac
STUB
    chmod 755 "${dir}/uname"
    mkdir -p "${dir}/fakedev/dev/net"
    ln -sf /dev/null "${dir}/fakedev/dev/fuse"
    ln -sf /dev/null "${dir}/fakedev/dev/net/tun"
    export DEVBOX_DEVICE_ROOT="${dir}/fakedev"
  fi
}

# Print the first logged line that is the devbox 'run' invocation, with the
# Docker 'container ' noun stripped so assertions are runtime-neutral.
# Usage: dv::logged_run_line <log-file>
dv::logged_run_line() {
  sed -n -e 's/^container run /run /p' -e 's/^run /run /p' "${1}" | head -n1 || true
}
