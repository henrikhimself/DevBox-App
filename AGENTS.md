#  Agent instructions
@AppleContainer/AGENTS.md
@Docker/AGENTS.md

## Ownership and layout

- Shared code lives in `Common/` (`image/`, `build/`, `host/`, `tests/`). Change
  shared behavior there, once; `AppleContainer/` and `Docker/` are thin frontends
  (command wrappers, `runtime/adapter.sh`, `Makefile`/`arch.mk`, runtime-only image
  hooks, a leaf `tests/run-tests.sh`). Do not copy shared files into a frontend.
- Only the adapter calls the runtime CLI. Runtime-specific rules stay scoped: the
  Darwin/arm64 and Apple backend checks apply to `AppleContainer/` only; the Linux
  amd64, local-socket, rootful/no-remap checks apply to `Docker/` only.
- `AppleContainer/tests/run-tests.sh` / `Docker/tests/run-tests.sh`: the shared feature
  suite for each runtime (real-runtime tests need the matching host).
- Build contexts under `<variant>/tmp/build-context/` are generated from an
  allowlist; never edit or commit them. Each allowlisted source is copied
  verbatim into the context; its path + SHA-256 are fingerprinted only to
  invalidate the build cache (no per-file integrity baseline is compared);
  never print their contents.

## Testing workflow

This DevBox cannot perform supported-host testing. During implementation,
use available source/static/document checks and independent stub-backed
contracts only. Defer all native builds, real container-backend tests,
image inspection, and interactive host checks until implementation and
documentation are complete. The user coordinates final human tests on
macOS arm64 and Linux amd64.

Missing host access/results must not block coding or documentation.
Implementation completion does not establish runtime verification; final
human results are required for runtime acceptance. This scheduling policy
does not authorize implementation or new security exceptions.
