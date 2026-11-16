#!/usr/bin/env bash
# run-suite.sh — Shared feature-suite runner. Not run directly: the leaf runners
# AppleContainer/tests/run-tests.sh and Docker/tests/run-tests.sh export
# DEVBOX_TEST_RUNTIME and DEVBOX_FRONTEND_DIR, then exec this file.
#
# Optional: DEVBOX_TEST_ONLY="F01 F02"  run only these IDs (also skips the
# clean-host precondition when every selected test is a stub test).
# Usage:
#   bash tests/run-tests.sh
#
# Tests invoke the repository scripts directly by path (no PATH changes
# required).
#
# Each test script is run in a subprocess. Results are collected and a summary
# is printed at the end. The script exits non-zero if any test failed.
#
# Precondition: no devbox-* containers may exist anywhere on the host (running
# or stopped) before this suite starts. F07, F24, and F28 (auto-detect/
# multi-running, for stop.sh, code.sh, and ssh.sh respectively) test
# host-wide running-container state by design, and F10 (no containers exist)
# tests host-wide any-state container state by design, so a pre-existing
# devbox (e.g. devbox-home, or a stopped devbox-home-keep) will cause false
# failures. This script fails fast with guidance if that precondition isn't
# met; F07, F10, F24, and F28 also carry their own standalone guard for when
# run individually.
#
# Test ordering notes:
#   F10 requires no devbox containers to exist in any state; it is placed
#   after F07-F09 which each clean up their own containers before exit.
#   F16, F24, and F28 create and stop their
#   own containers, but each cleans up in its own trap before its subprocess
#   exits, so their placement at the end of the array (after F10) does not
#   leak state back into F10 — each test's dv::cleanup completes within its own
#   subprocess lifetime before the next TESTS entry runs. All other tests are
#   independent and run in feature-number order.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=testenv.sh
source "${TESTS_DIR}/testenv.sh"

# ── Preflight ────────────────────────────────────────────────────────────────

REPO_DIR="${TENV_FRONTEND_DIR}"
for s in init run stop show discard code ssh forward; do
  [[ -f "${REPO_DIR}/${s}.sh" ]] || {
    printf '%s\n' "❌ ./${s}.sh not found at ${REPO_DIR}. Run this from a checkout of the repository." >&2
    exit 1
  }
done

# Applicability (applicability.tsv): id, file, scope (common|apple|docker), mode (real|stub).
# A test whose scope does not include the runtime under test is reported N/A with
# its documented replacement; it is never silently dropped.
dv::test_scope() { awk -F'\t' -v f="${1}" '$2 == f { print $3 }' "${TESTS_DIR}/applicability.tsv" || true; }
dv::test_mode() { awk -F'\t' -v f="${1}" '$2 == f { print $4 }' "${TESTS_DIR}/applicability.tsv" || true; }
dv::test_note() { awk -F'\t' -v f="${1}" '$2 == f { print $5 }' "${TESTS_DIR}/applicability.tsv" || true; }
dv::out_of_scope() { # scope -> 0 when a runtime-specific scope is not the runtime under test
  [[ "${1}" != common && "${1}" != "${DEVBOX_TEST_RUNTIME}" ]]
}
dv::selected() { # test_file -> 0 when selected by DEVBOX_TEST_ONLY (or no filter)
  [[ -z "${DEVBOX_TEST_ONLY:-}" ]] && return 0
  case " ${DEVBOX_TEST_ONLY} " in *" ${1%%-*} "*) return 0 ;; esac
  return 1
}

# ── Test sequence ────────────────────────────────────────────────────────────

TESTS=(
  F01-init-arg-and-profile-validation.sh
  F02-init-volume-initialization-idempotent.sh
  F03-run-cli-input-validation.sh
  F04-run-requires-initialized-profile.sh
  F05-run-requires-devbox-image.sh
  F06-run-blocks-ephemeral-when-kept-exists.sh
  F07-stop-auto-detect-and-multi-running-error.sh
  F08-stop-with-profile-selection.sh
  F09-stop-force-remove-kept-container.sh
  F11-show-lists-profile-and-mount-details.sh
  F12-discard-arg-and-profile-validation.sh
  F13-discard-running-container-guard.sh
  F14-discard-confirmation-required-without-y.sh
  F15-discard-y-removes-profile-volumes.sh
  F16-show-lists-stopped-container.sh
  F17-run-requires-workspace-for-new-keep.sh
  F18-run-resumes-kept-container-without-workspace.sh
  F19-run-resume-blocked-by-port-conflict.sh
  F20-run-warns-on-new-keep-port-collision.sh
  F21-code-requires-running-profile.sh
  F22-code-writes-ssh-block-and-invokes-code.sh
  F23-code-warns-when-include-missing.sh
  F24-code-auto-detect-and-multi-running-error.sh
  F25-ssh-requires-running-profile.sh
  F26-ssh-writes-ssh-block-and-invokes-ssh.sh
  F27-ssh-warns-when-include-missing.sh
  F28-ssh-auto-detect-and-multi-running-error.sh
  F29-run-auto-selects-pool-port.sh
  F30-run-auto-select-avoids-existing-port-conflict.sh
  F31-run-fails-when-pool-exhausted.sh
  F32-forward-requires-port-argument.sh
  F33-forward-cli-port-syntax-validation.sh
  F34-forward-requires-running-profile.sh
  F35-forward-close-with-nothing-active-errors.sh
  F36-forward-close-without-v-and-no-matches-errors.sh
  F37-forward-bulk-close-with-v-errors-when-none-active.sh
  F38-forward-bulk-close-without-v-errors-when-none-active.sh
  F39-forward-list-with-nothing-active.sh
  F40-forward-list-scoped-with-nothing-active.sh
  F41-forward-list-mutually-exclusive-with-p-or-D.sh
  F45-forward-identityfile-only-for-existing-keys.sh
  F46-show-inspects-each-container-once.sh
  F48-run-grants-full-capabilities.sh
  F50-ssh-tmux-session-command.sh
  F51-run-mounts-under-default-workspace-project-name.sh
  F52-run-keeps-exact-destination-with-explicit-t.sh
  F53-run-fallback-name-for-root-workspace.sh
  F54-run-keep-resume-keeps-named-mount.sh
  F55-show-displays-named-target.sh
  F56-ssh-tmux-uses-named-workspace-target.sh
  F57-show-lists-init-only-profile.sh
  F58-validate-rejects-hyphen.sh
  F59-discard-removes-ssh-config-block.sh
  F60-backup-archives-profile-volumes.sh
  F61-restore-creates-absent-profile-volumes.sh
  F62-backup-full-archives-docker-state.sh
  F63-restore-full-backup-scope-message.sh
  F64-restore-confirmation-required-without-y.sh
  F65-restore-rejects-missing-scope.sh
  F66-run-docker-launch-uses-privileged.sh
)
# Precondition (clean host) only matters when a selected, applicable test uses the real runtime.
dv::needs_clean() { local t scope mode; for t in "${TESTS[@]}"; do dv::selected "${t}" || continue; scope="$(dv::test_scope "${t}")"; mode="$(dv::test_mode "${t}")"; dv::out_of_scope "${scope}" && continue; [[ "${mode}" == real ]] && return 0; done; return 1; }

if dv::needs_clean \
   && dv::all_devbox_names | grep -q .; then
  printf '%s\n' '❌ Other devbox containers already exist (running or stopped) on this host.' >&2
  printf '%s\n' 'This suite requires a clean state (F07/F10 test host-wide container behavior).' >&2
  printf '%s\n' 'Stop/remove each devbox container first (./stop.sh -v <profile-name>, then ./discard.sh -v <profile-name> if kept), then retry.' >&2
  dv::all_devbox_names >&2
  exit 1
fi


passed=0
failed=0
skipped=0
failures=()

na=0
for test_file in "${TESTS[@]}"; do
  dv::selected "${test_file}" || continue
  scope_of="$(dv::test_scope "${test_file}")"
  if dv::out_of_scope "${scope_of}"; then
    note_of="$(dv::test_note "${test_file}")"
    printf '\xe2\x8f\xad\xef\xb8\x8f   N/A   %s\n          %s-specific; replacement: %s\n' "${test_file}" "${scope_of}" "${note_of}"
    (( na++ )) || true
    continue
  fi
  script="${TESTS_DIR}/${test_file}"
  # Decide pass/fail/skip on the child's exit status:
  #   0 = PASS, 1 = FAIL, 2 = SKIP (runtime prerequisite not met)
  # The PASS marker in output is only a secondary sanity indicator.
  result="$(bash "${script}" 2>&1)" && rc=$? || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    printf '✅  PASS  %s\n' "${test_file}"
    if [[ "${result}" != *'PASS'* ]]; then
      printf '          note: exited 0 but did not print the expected PASS marker\n'
    fi
    (( passed++ )) || true
  elif [[ "${rc}" -eq 2 ]]; then
    printf '⏭️   SKIP  %s\n' "${test_file}"
    while IFS= read -r line; do
      printf '          %s\n' "${line}"
    done <<< "${result}"
    (( skipped++ )) || true
  else
    printf '❌  FAIL  %s\n' "${test_file}"
    # Indent the failure output for readability
    while IFS= read -r line; do
      printf '          %s\n' "${line}"
    done <<< "${result}"
    (( failed++ )) || true
    failures+=("${test_file}")
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

total=$(( passed + failed + skipped ))
if [[ "${skipped}" -gt 0 ]]; then
  printf '\n%d/%d tests passed (%d skipped)\n' "${passed}" "$(( passed + failed ))" "${skipped}"
else
  printf '\n%d/%d tests passed\n' "${passed}" "${total}"
fi

if [[ "${failed}" -gt 0 ]]; then
  printf '\nFailed tests:\n'
  for f in "${failures[@]}"; do
    printf '  • %s\n' "${f}"
  done
  exit 1
fi
