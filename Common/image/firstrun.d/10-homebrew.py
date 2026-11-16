#!/usr/bin/env python3
"""Homebrew first-run installer."""
import os
import shutil
import subprocess
import sys
import tempfile

TOOL_ID = "homebrew"
TOOL_NAME = "Homebrew"
DEPENDS = ""
INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])
LINUXBREW_BREW = "/home/linuxbrew/.linuxbrew/bin/brew"


def _has_brew():
    return shutil.which("brew") is not None or os.access(LINUXBREW_BREW, os.X_OK)


def install_tool():
    if _has_brew():
        return 0
    fd, installer = tempfile.mkstemp(prefix="homebrew-install-")
    os.close(fd)
    try:
        if subprocess.run(
            ["curl", "-fsSL", INSTALL_URL, "-o", installer]
        ).returncode != 0:
            return 1
        env = dict(os.environ, NONINTERACTIVE="1")
        if subprocess.run(["bash", installer], env=env).returncode != 0:
            return 1
    finally:
        # ``rm -f`` in the shell is idempotent: remove once on the way out.
        if os.path.exists(installer):
            os.remove(installer)
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
