#!/usr/bin/env bash
set -uo pipefail

# F46 - show inspects each container once

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/show.sh" ]] || dv::fail "./show.sh not found at ${REPO_DIR}"

dv::make_tmpdir
FAKE_BIN="${TENV_TMPDIR}/bin"
LOG_FILE="${TENV_TMPDIR}/container.log"
mkdir -p "${FAKE_BIN}"

# Fake 'container' stub: logs every invocation and answers the calls show.sh
# makes (system status, volume ls, list, inspect per container) with Apple
# Container CLI output and JSON shapes.
cat > "${FAKE_BIN}/container" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_CONTAINER_LOG:?}"
printf '%s\n' "$*" >> "${log_file}"

case "${1:-}" in
  system)
    # 'container system status' must report the backend as running.
    printf 'status running\n'
    ;;
  volume)
    case "${2:-}" in
      ls)
        # dv::all_profile_names derives profiles from the init.sh volume pair.
        printf '%s\n' '[{"id":"devbox-tplano2a"},{"id":"devbox-tplano2a-docker"},{"id":"devbox-tplano2b"},{"id":"devbox-tplano2b-docker"}]'
        exit 0
        ;;
      inspect)
        # Name-aware: only the four real profile volumes exist, so the
        # '<profile>-docker' candidates dv::fail the pair check in
        # dv::all_profile_names and no phantom profiles are produced.
        case "${3:-}" in
          devbox-tplano2a|devbox-tplano2a-docker|devbox-tplano2b|devbox-tplano2b-docker) exit 0 ;;
          *) exit 1 ;;
        esac
        ;;
    esac
    ;;
  list)
    # dv::all_devbox_names uses: container list --all --format json
    printf '%s\n' '[{"id":"devbox-tplano2a","status":{"state":"running"}},{"id":"devbox-tplano2b","status":{"state":"stopped"}}]'
    exit 0
    ;;
  inspect)
    case "${2:-}" in
      devbox-tplano2a)
        cat <<'JSON'
[{"id":"devbox-tplano2a","status":{"state":"running"},"configuration":{"labels":{"devbox.workspace-target":"/workspace"},"mounts":[{"source":"devbox-tplano2a-home","destination":"/home"},{"source":"devbox-tplano2a-docker","destination":"/data/docker"},{"source":"/tmp/ws-a","destination":"/workspace"}],"publishedPorts":[{"hostPort":22111,"containerPort":2222,"proto":"tcp"}]}}]
JSON
        exit 0
        ;;
      devbox-tplano2b)
        cat <<'JSON'
[{"id":"devbox-tplano2b","status":{"state":"stopped"},"configuration":{"labels":{"devbox.workspace-target":"/code"},"mounts":[{"source":"devbox-tplano2b-home","destination":"/home"},{"source":"devbox-tplano2b-docker","destination":"/data/docker"},{"source":"/tmp/ws-b","destination":"/code"}],"publishedPorts":[{"hostPort":22112,"containerPort":2222,"proto":"tcp"}]}}]
JSON
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
esac

exit 0
EOF
chmod 755 "${FAKE_BIN}/container"

# Step 1: run show.sh under the fake container runtime.
out="$(CONTAINER_CMD=container FAKE_CONTAINER_LOG="${LOG_FILE}" PATH="${FAKE_BIN}:${PATH}" bash "${REPO_DIR}/show.sh" 2>&1)" \
  || dv::fail "show.sh failed: ${out}"

# Step 2: output still contains expected rows/values.
printf -v row_a '%s\t%s\t%s\t%s\t%s' 'tplano2a' 'running' '22111' '/tmp/ws-a' '/workspace'
printf -v row_b '%s\t%s\t%s\t%s\t%s' 'tplano2b' 'stopped' '22112' '/tmp/ws-b' '/code'
[[ "${out}" == *"${row_a}"* ]] || dv::fail "expected row for tplano2a, got: ${out}"
[[ "${out}" == *"${row_b}"* ]] || dv::fail "expected row for tplano2b, got: ${out}"

# Step 3: exactly one inspect per listed container.
inspect_count="$(grep -c '^inspect ' "${LOG_FILE}" || true)"
[[ "${inspect_count}" -eq 2 ]] \
  || {
    log_content="$(cat "${LOG_FILE}")"
    dv::fail "expected exactly 2 inspect calls (one per container), got ${inspect_count}: ${log_content}"
  }

printf 'PASS\n'
