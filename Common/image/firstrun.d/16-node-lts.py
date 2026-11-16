#!/usr/bin/env python3
"""Node LTS first-run installer (installs the pinned version into fnm's FNM_DIR).

Depends on: fnm
"""
import json
import os
import shutil
import subprocess
import sys

TOOL_ID = "node-lts"
TOOL_NAME = "Node LTS (via fnm)"
DEPENDS = "fnm"

# Pinned Node version to install. This is the version ``30-fnm.sh``'s login
# shell will later place on PATH once fnm has resolved it under ``FNM_DIR``.
NODE_VERSION = "26.13.1"

# pnpm is provided via corepack (ships with the fnm-installed node). A range
# spec rather than a hard version keeps ``corepack prepare`` fetchable for the
# lifetime of the image; bump the line when pnpm's major version advances.
PNPM_SPEC = "latest"

# Homebrew's Linuxbrew (Linux-only) sysroot fallback for the fnm binary.
LINUXBREW_FNM = "/home/linuxbrew/.linuxbrew/bin/fnm"

# fnm's default ``FNM_DIR``, used only as a last resort when ``fnm env`` is
# unavailable (see :func:`_resolve_fnm_dir`). Users frequently override it, so
# parsing ``fnm env`` is preferred over assuming this value.
FNM_DIR_DEFAULT = os.path.expanduser(os.path.expandvars("${HOME}/.fnm"))

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])


def _fnm_executable():
    """Locate a runnable ``fnm``: prefer a PATH lookup, then fall back to the
    Linuxbrew sysroot ``/home/linuxbrew/.linuxbrew/bin/fnm`` (Linux only).
    A Linuxbrew ``fnm`` is not always on PATH, so callers must use the
    returned full path rather than the bare name ``"fnm"`` (fnm is not on
    PATH during first-run, mirroring ``15-fnm.py``'s brew discovery)."""
    found = shutil.which("fnm")
    if found is not None:
        return found
    return LINUXBREW_FNM if os.access(LINUXBREW_FNM, os.X_OK) else None


def _resolve_fnm_dir(fnm):
    """Resolve ``FNM_DIR`` the way ``30-fnm.sh`` does at login: parse ``fnm env``.

    ``30-fnm.sh`` runs ``fnm env`` inside bash at login; a Python subprocess
    cannot infer its shell, so pass ``--json`` (shell-independent, and fnm
    emits ``FNM_DIR`` verbatim as a JSON key). The reported value is fnm's
    single source of truth, so node installs into exactly the directory
    ``30-fnm.sh`` will later point the user's PATH at (fnm's default is
    ``${HOME}/.fnm``, but users may override it -- parsing avoids assuming
    either)."""
    try:
        proc = subprocess.run(
            [fnm, "env", "--json"],
            capture_output=True,
            text=True,
            check=True,
        )
        value = json.loads(proc.stdout).get("FNM_DIR")
    except (subprocess.CalledProcessError, ValueError):
        value = None
    if not value:
        return FNM_DIR_DEFAULT
    return os.path.expanduser(os.path.expandvars(value))


def _ensure_pnpm(fnm_dir, env):
    """Install pnpm as a corepack shim enabled by the fnm-installed node.

    ``corepack enable`` + ``prepare <spec> --activate`` are idempotent, so this
    runs on every first run and retries a previously failed install. corepack
    is bundled with every fnm-installed Node (>=16); if a pre-Node-16 node were
    somehow selected, ``corepack`` is absent and :func:`subprocess.run` raises
    ``OSError`` (a ``subprocess.CalledProcessError`` subclass), which we treat
    as "nothing to install" rather than a hard failure.
    """
    bin_dir = os.path.join(fnm_dir, "node-versions", "v" + NODE_VERSION, "bin")
    corepack = os.path.join(bin_dir, "corepack")
    for args in (
        [corepack, "enable"],
        [corepack, "prepare", "pnpm@" + PNPM_SPEC, "--activate"],
    ):
        try:
            rc = subprocess.run(args, env=env, check=False).returncode
        except OSError:
            return 0
        if rc != 0:
            return 1
    return 0


def _already_installed(fnm_dir):
    """True if the pinned version was already installed under ``FNM_DIR``.

    fnm stores each version as ``<FNM_DIR>/node-versions/v<major>.<minor>.<patch>``
    (note the ``v`` prefix)."""
    return os.path.isdir(os.path.join(fnm_dir, "node-versions", "v" + NODE_VERSION))


def install_tool():
    fnm = _fnm_executable()
    if fnm is None:
        print(
            "fnm is not installed; cannot install Node. "
            "Run the fnm first-run installer first.",
            file=sys.stderr,
        )
        return 1
    fnm_dir = _resolve_fnm_dir(fnm)
    if _already_installed(fnm_dir):
        return 0
    # fnm reads ``FNM_DIR`` from the environment; pin it so the install lands in
    # the same directory ``30-fnm.sh``'s ``fnm env`` reports for the login
    # shell. ``FNM_NODE_DIST_MIRROR`` (https://nodejs.org/dist) is inherited from
    # the environment (or fnm's default), so no per-call copy is needed.
    env = dict(os.environ, FNM_DIR=fnm_dir)
    if subprocess.run(
        [fnm, "install", NODE_VERSION],  # positional exact version
        env=env,
        check=False,
    ).returncode != 0:
        return 1
    # pnpm ships as a corepack shim; run it even when Node was already present
    # (idempotent) so a failed install is retried on the next first run.
    return _ensure_pnpm(fnm_dir, dict(os.environ, FNM_DIR=fnm_dir))


def main(argv):
    if len(argv) < 2:
        print(USAGE, file=sys.stderr)
        return 1
    sub = argv[1]
    if sub == "id":
        print(TOOL_ID)
        return 0
    if sub == "name":
        print(TOOL_NAME)
        return 0
    if sub == "depends":
        print(DEPENDS, end="")
        return 0
    if sub == "meta":
        print(TOOL_ID)
        print(TOOL_NAME)
        return 0
    if sub == "install":
        return install_tool()
    print(USAGE, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
