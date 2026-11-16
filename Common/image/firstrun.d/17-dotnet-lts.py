#!/usr/bin/env python3
""".NET SDK first-run installer (installs the LTS channel to ${HOME}/.dotnet).

Depends on: (none)

Installs the .NET SDK to a user-writable location ($HOME/.dotnet) and lets the
login shell's ``20-dotnet.sh`` put it on PATH. Mirrors the former Containerfile
step::

    curl ... /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel LTS --install-dir /opt/dotnet

The install root changed from the root-owned ``/opt/dotnet`` (a build-time root
step) to ``${HOME}/.dotnet`` because the first-run installer runs as the
non-root ``bob`` user, and ``20-dotnet.sh`` is now ``$HOME``-relative.
"""
import os
import subprocess
import sys
import tempfile

TOOL_ID = "dotnet-lts"
TOOL_NAME = ".NET SDK"
DEPENDS = ""

# The official .NET install script (mirrors the Containerfile source URL).
DOTNET_INSTALL_URL = (
    "https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.sh"
)
# LTS channel, matching the Containerfile ``--channel LTS``.
DOTNET_CHANNEL = "LTS"

# User-writable install root; the login shell's ``20-dotnet.sh`` adds this (and
# ``${DOTNET_ROOT}/tools``) to PATH. ``dotnet-install.sh --install-dir`` installs
# the SDK here and drops the ``dotnet`` executable at ``${DOTNET_HOME}/dotnet``.
DOTNET_HOME = os.path.join(os.path.expanduser("~"), ".dotnet")
DOTNET_INSTALLER = os.path.join(DOTNET_HOME, "dotnet-install.sh")
DOTNET_EXE = os.path.join(DOTNET_HOME, "dotnet")

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])


def _already_installed():
    """True if the SDK is already installed (``dotnet`` present under DOTNET_HOME)."""
    return os.path.exists(DOTNET_EXE)


def install_tool():
    if _already_installed():
        return 0
    os.makedirs(DOTNET_HOME, exist_ok=True)
    fd, installer = tempfile.mkstemp(prefix="dotnet-install-")
    os.close(fd)
    try:
        # Download the install script.
        if subprocess.run(
            ["curl", "-fsSL", DOTNET_INSTALL_URL, "-o", installer]
        ).returncode != 0:
            return 1
        # Original did ``chmod +x``; run it directly (it is a ``sh`` script).
        os.chmod(installer, 0o755)
        if subprocess.run(
            [installer, "--channel", DOTNET_CHANNEL, "--install-dir", DOTNET_HOME]
        ).returncode != 0:
            return 1
    finally:
        # Idempotent cleanup: ``rm -f`` semantics, remove once on the way out.
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
