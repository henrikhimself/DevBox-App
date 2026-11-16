#!/usr/bin/env bash
set -euo pipefail

dv::gh_json() {
  local target="$1"
  local repo="$2"
  local version="$3"

  mkdir -p "$(dirname -- "${target}")"
  curl -fsSL -o "${target}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/tags/v${version}"
}

dv::gh_release() {
  local target="$1"
  local release_json="$2"
  local asset_name="$3"
  local download_url
  local digest

  mkdir -p "$(dirname -- "${target}")"
  download_url="$(jq -er --arg asset "${asset_name}" '.assets[] | select(.name == $asset) | .browser_download_url' "${release_json}")"
  digest="$(jq -er --arg asset "${asset_name}" '.assets[] | select(.name == $asset) | .digest | sub("^sha256:"; "")' "${release_json}")"
  curl -fsSL -o "${target}" "${download_url}"
  if ! printf '%s  %s\n' "${digest}" "${target}" | sha256sum -c -; then
    rm -f "${target}"
    return 1
  fi
}

if [[ $# -lt 1 ]]; then
  printf '%s\n' "Usage: $0 <gh-json|gh-release> <args...>" >&2
  exit 1
fi

case "$1" in
  gh-json)
    shift
    dv::gh_json "$@"
    ;;
  gh-release)
    shift
    dv::gh_release "$@"
    ;;
  *)
    printf '%s\n' "Unknown command: $1" >&2
    exit 1
    ;;
esac
