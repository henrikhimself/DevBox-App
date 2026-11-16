#!/usr/bin/env python3
"""Fast Node Manager (fnm) first-run installer.
Depends on: homebrew
"""
import os
import shutil
import subprocess
import sys

TOOL_ID = "fnm"
TOOL_NAME = "Fast Node Manager"
DEPENDS = "homebrew"

# Homebrew's Linuxbrew (Linux-only) sysroot fallback.
LINUXBREW_BREW = "/home/linuxbrew/.linuxbrew/bin/brew"


def _brew_executable():
    """Locate a runnable ``brew``: prefer a PATH lookup, then fall back to the
    Linuxbrew sysroot ``/home/linuxbrew/.linuxbrew/bin/brew`` (Linux only).
    A Linuxbrew ``brew`` is not always on PATH, so callers must use the
    returned full path rather than the bare name ``"brew"``."""
    found = shutil.which("brew")
    if found is not None:
        return found
    return LINUXBREW_BREW if os.access(LINUXBREW_BREW, os.X_OK) else None

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])
HOMEBREW_NOT_INSTALLED = (
    "Homebrew is not installed; cannot install fnm. "
    "Run the homebrew first-run installer first."
)


def install_tool():
    if shutil.which("fnm") is not None:
        return 0
    brew = _brew_executable()
    if brew is None:
        print(HOMEBREW_NOT_INSTALLED, file=sys.stderr)
        return 1
    # --no-ask skips Homebrew's interactive "Do you want to proceed with the
    # installation? [y/n]" prompt so the first-run run stays non-interactive.
    if subprocess.run([brew, "install", "--no-ask", "fnm"]).returncode != 0:
        return 1
    return 0


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
