#!/usr/bin/env bash
# Assemble a minimal, per-specialization image build context from an explicit
# allowlist, or print a fingerprint of the allowlisted sources.
#
#   prepare-context.sh --runtime-dir DIR --downloads DIR --out DIR
#   prepare-context.sh --fingerprint --runtime-dir DIR
#
# --runtime-dir  specialization directory (AppleContainer/ or Docker/); its
#                runtime/image/s6-x/*.sh hooks are overlaid onto s6-x/
# --downloads    directory holding the already-verified native archives
#                s6-overlay-arch.tar.xz, s6-overlay-noarch.tar.xz
# --out          context directory to (re)create; only a directory carrying
#                this script's ownership marker is ever replaced
#
# Allowlist (nothing else is copied): Common/image/Containerfile,
# Common/image/{profile.d,firstrun.d,script,s6-x}/* and root/Config/* (regular
# files only), <runtime-dir>/runtime/image/s6-x/*.sh, and the three archives.
# Rejects symlinks, nested directories and hook/common name collisions.
# Never prints file contents.
# Bash 3.2 compatible; uses only POSIX-portable utilities plus sha256sum or shasum.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$(cd "${HERE}/.." && pwd)"
IMAGE_SRC="${COMMON_DIR}/image"
CONFIG_SRC="${COMMON_DIR}/.."/Config
MARKER='.devbox-build-context'
COMMON_DIRS=(profile.d firstrun.d script s6-x)
ARCHIVES=(s6-overlay-arch.tar.xz s6-overlay-noarch.tar.xz)

dv::fail() { printf '❌ %s\n' "$1" >&2; exit 1; }

dv::sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else dv::fail 'sha256sum or shasum is required'; fi
}
dv::sha_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

RUNTIME_DIR=''; DOWNLOADS=''; OUT=''; FINGERPRINT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-dir) RUNTIME_DIR="${2:?}"; shift 2 ;;
    --downloads) DOWNLOADS="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --fingerprint) FINGERPRINT=1; shift ;;
    *) dv::fail "unknown argument: $1" ;;
  esac
done
[[ -n "${RUNTIME_DIR}" && -d "${RUNTIME_DIR}" ]] || dv::fail '--runtime-dir must name an existing directory'
RUNTIME_DIR="$(cd "${RUNTIME_DIR}" && pwd -P)"
HOOKS_SRC="${RUNTIME_DIR}/runtime/image/s6-x"

# List allowlisted sources as "<kind>\t<staged-relpath>\t<source-path>", sorted.
# Fails on symlinks, nested directories and collisions.
dv::list_sources() {
  local d f name
  printf 'file\tContainerfile\t%s\n' "${IMAGE_SRC}/Containerfile"
  [[ -f "${IMAGE_SRC}/Containerfile" && ! -L "${IMAGE_SRC}/Containerfile" ]] || dv::fail 'Common/image/Containerfile missing or a symlink'
  for d in "${COMMON_DIRS[@]}"; do
    [[ -d "${IMAGE_SRC}/${d}" && ! -L "${IMAGE_SRC}/${d}" ]] || dv::fail "Common/image/${d} missing or a symlink"
    for f in "${IMAGE_SRC}/${d}"/*; do
      [[ -e "${f}" ]] || continue
      name="$(basename -- "${f}")"
      # Python bytecode caches are build artefacts, never context sources.
      [[ "${name}" == __pycache__ && -d "${f}" ]] && continue
      [[ ! -L "${f}" ]] || dv::fail "symlink not allowed in context sources: ${d}/${name}"
      [[ -f "${f}" ]] || dv::fail "nested directory or special file not allowed in context sources: ${d}/${name}"
      printf 'file\t%s/%s\t%s\n' "${d}" "${name}" "${f}"
    done
    # dotfiles are never part of the allowlist; refuse them rather than skip silently
    for f in "${IMAGE_SRC}/${d}"/.[!.]*; do
      [[ -e "${f}" ]] && dv::fail "hidden file not allowed in context sources: ${d}/$(basename -- "${f}")"
    done
  done
  # Root Config dir holds secret/config material:
  if [[ -d "${CONFIG_SRC}" ]]; then
    for f in "${CONFIG_SRC}"/*; do
      [[ -e "${f}" ]] || continue
      name="$(basename -- "${f}")"
      [[ ! -L "${f}" ]] || dv::fail "symlink not allowed in Config sources: ${name}"
      [[ -f "${f}" ]] || dv::fail "nested directory or special file not allowed in Config sources: ${name}"
      printf 'file\tConfig/%s\t%s\n' "${name}" "${f}"
    done
    for f in "${CONFIG_SRC}"/.[!.]*; do
      [[ -e "${f}" ]] && dv::fail "hidden file not allowed in Config sources: $(basename -- "${f}")"
    done
  fi
  if [[ -d "${HOOKS_SRC}" ]]; then
    for f in "${HOOKS_SRC}"/*; do
      [[ -e "${f}" ]] || continue
      name="$(basename -- "${f}")"
      [[ ! -L "${f}" ]] || dv::fail "symlink not allowed in runtime hooks: ${name}"
      [[ -f "${f}" && "${name}" == *.sh ]] || dv::fail "runtime hook must be a regular .sh file: ${name}"
      if [[ -e "${IMAGE_SRC}/s6-x/${name}" ]]; then
        dv::fail "runtime hook collides with a common file: s6-x/${name}"
      fi
      printf 'file\ts6-x/%s\t%s\n' "${name}" "${f}"
    done
  fi
}

dv::sorted_sources() { dv::list_sources | LC_ALL=C sort -t "$(printf '\t')" -k2,2; }

if [[ "${FINGERPRINT}" -eq 1 ]]; then
  {
    dv::sorted_sources | while IFS=$'\t' read -r _ rel src; do
      file_hash="$(dv::sha "${src}")"
      printf '%s %s\n' "${rel}" "${file_hash}"
    done
    script_hash="$(dv::sha "${BASH_SOURCE[0]}")"
    printf 'script %s\n' "${script_hash}"
  } | dv::sha_stdin
  exit 0
fi

[[ -n "${DOWNLOADS}" && -d "${DOWNLOADS}" ]] || dv::fail '--downloads must name an existing directory'
[[ -n "${OUT}" ]] || dv::fail '--out is required'
for a in "${ARCHIVES[@]}"; do
  [[ -f "${DOWNLOADS}/${a}" && ! -L "${DOWNLOADS}/${a}" ]] || dv::fail "missing verified download: ${DOWNLOADS}/${a}"
done

# Resolve --out without requiring it to exist; refuse dangerous targets.
mkdir -p "$(dirname -- "${OUT}")"
out_dir="$(cd "$(dirname -- "${OUT}")" && pwd -P)"
out_name="$(basename -- "${OUT}")"
OUT="${out_dir}/${out_name}"
case "${OUT}" in
  /|"${COMMON_DIR}"|"${COMMON_DIR}"/*|"${RUNTIME_DIR}"|"${HOME:-/nonexistent}") dv::fail "refusing unsafe context directory: ${OUT}" ;;
esac
if [[ -e "${OUT}" || -L "${OUT}" ]]; then
  [[ -d "${OUT}" && ! -L "${OUT}" && -f "${OUT}/${MARKER}" ]] || dv::fail "refusing to replace a directory this tool did not create: ${OUT}"
  rm -rf "${OUT}"
fi

umask 077
dv::cleanup_on_failure() { if [[ "${STAGED_OK:-0}" -ne 1 ]]; then rm -rf "${OUT}"; fi; }
trap dv::cleanup_on_failure EXIT
mkdir -p "${OUT}"
: > "${OUT}/${MARKER}"

dv::sorted_sources | while IFS=$'\t' read -r _ rel src; do
  mkdir -p "${OUT}/$(dirname -- "${rel}")"
  cp "${src}" "${OUT}/${rel}"
done
mkdir -p "${OUT}/tmp"
for a in "${ARCHIVES[@]}"; do
  cp "${DOWNLOADS}/${a}" "${OUT}/tmp/${a}"
  chmod 644 "${OUT}/tmp/${a}"
done

# The context is assembled from the allowlist only. No per-file integrity
# baseline is compared: fingerprints (relpath + SHA-256) are emitted only for
# build-cache invalidation.

# Every Containerfile COPY source must exist in the context.
# shellcheck disable=SC2312 # process substitution keeps loop in current shell so dv::fail's exit aborts the script
while IFS= read -r line; do
  for s in ${line}; do
    # shellcheck disable=SC2086 # glob expansion of the COPY source is intended
    ls ${OUT}/${s} >/dev/null 2>&1 || dv::fail "Containerfile COPY source not in context: ${s}"
  done
done < <(sed -n 's/^COPY[[:space:]]\{1,\}\(--[^ ]\{1,\}[[:space:]]\{1,\}\)*\([^ ]\{1,\}\)[[:space:]]\{1,\}[^ ]\{1,\}$/\2/p' "${OUT}/Containerfile")

# Context directories are private to the invoking user.
find "${OUT}" -type d -exec chmod 700 {} +
STAGED_OK=1
printf '✅ Prepared build context: %s\n' "${OUT}"
