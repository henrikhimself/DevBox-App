#!/usr/bin/env bash
set -uo pipefail

# F03 - run CLI input validation

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::make_tmpdir
trap dv::cleanup_tmpdir EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

# Step 1: no args
out="$(bash "${REPO_DIR}/run.sh" 2>&1)" && dv::fail "expected failure for no-args" || true
[[ "${out}" == *"Usage:"* ]] || dv::fail "expected 'Usage:' for no-args, got: ${out}"

# Step 2: workspace path does not exist
out="$(bash "${REPO_DIR}/run.sh" /path/that/does/not/exist 2>&1)" && dv::fail "expected failure for missing workspace" || true
[[ "${out}" == *"Workspace path does not exist"* ]] || dv::fail "expected workspace-path error, got: ${out}"

# Step 3: invalid memory
out="$(bash "${REPO_DIR}/run.sh" -m 0 "${TENV_TMPDIR}" 2>&1)" && dv::fail "expected failure for -m 0" || true
[[ "${out}" == *"memory-gb"* ]] || dv::fail "expected 'memory-gb' error, got: ${out}"

# Step 4: invalid cpu cores
out="$(bash "${REPO_DIR}/run.sh" -c 0 "${TENV_TMPDIR}" 2>&1)" && dv::fail "expected failure for -c 0" || true
[[ "${out}" == *"cpu-cores"* ]] || dv::fail "expected 'cpu-cores' error, got: ${out}"

# Step 5: invalid port
out="$(bash "${REPO_DIR}/run.sh" -p 70000 "${TENV_TMPDIR}" 2>&1)" && dv::fail "expected failure for -p 70000" || true
[[ "${out}" == *"host-port"* ]] || dv::fail "expected 'host-port' error, got: ${out}"

# Step 6: relative target path
out="$(bash "${REPO_DIR}/run.sh" -t relative/path "${TENV_TMPDIR}" 2>&1)" && dv::fail "expected failure for relative target-path" || true
[[ "${out}" == *"target-path"* ]] || dv::fail "expected 'target-path' error, got: ${out}"

printf 'PASS\n'
