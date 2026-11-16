#!/usr/bin/env python3
"""PowerShell first-run installer (installs the PowerShell global tool).

Depends on: dotnet-lts

Installs PowerShell as a ``dotnet`` global tool into a user-writable location
(${HOME}/.pwsh). Mirrors the former Containerfile step::

    dotnet tool install --tool-path /opt/powershell PowerShell

The install root changed from the root-owned ``/opt/powershell`` to
``${HOME}/.pwsh`` (the first-run installer runs as the non-root ``bob`` user,
and ``30-pwsh.sh`` is now ``$HOME``-relative).

The former Containerfile appended ``/opt/powershell/pwsh`` to ``/etc/shells``;
that writes a root-owned file, so the (non-root) first-run installer does not
attempt it. Adding pwsh as a login shell for ssh still needs an admin.
"""
import os
import subprocess
import sys

TOOL_ID = "powershell"
TOOL_NAME = "PowerShell"
DEPENDS = "dotnet-lts"

# User-writable install root; the login shell's ``30-pwsh.sh`` adds this to PATH.
POWSHELL_HOME = os.path.join(os.path.expanduser("~"), ".pwsh")
POWSHELL_EXE = os.path.join(POWSHELL_HOME, "pwsh")

# The SDK the tool is installed against (see ``17-dotnet-lts.py``). Both the SDK
# and the tool live under the same ${HOME} so neither needs a writable /opt.
DOTNET_HOME = os.path.join(os.path.expanduser("~"), ".dotnet")
DOTNET_EXE = os.path.join(DOTNET_HOME, "dotnet")

# NuGet package name and pinned version for the PowerShell global tool.
POWSHELL_PACKAGES = "PowerShell"
POWSHELL_VERSION = "7.6.10"

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])

DOTNET_NOT_INSTALLED = (
    ".NET SDK (dotnet-lts) is not installed; cannot install PowerShell. "
    "Run the .NET SDK first-run installer first."
)


def _already_installed():
    return os.path.exists(POWSHELL_EXE)


def install_tool():
    if _already_installed():
        return 0
    # ``dotnet tool install`` needs the SDK; locate it by path (not PATH) so this
    # works regardless of login-shell ordering.
    if not os.path.exists(DOTNET_EXE):
        print(DOTNET_NOT_INSTALLED, file=sys.stderr)
        return 1
    os.makedirs(POWSHELL_HOME, exist_ok=True)
    # Mirror ``20-dotnet.sh``'s env: DOTNET_ROOT points at the SDK, telemetry off.
    env = dict(os.environ, DOTNET_ROOT=DOTNET_HOME, DOTNET_CLI_TELEMETRY_OPTOUT="1")
    if subprocess.run(
        [
            DOTNET_EXE,
            "tool",
            "install",
            "--tool-path",
            POWSHELL_HOME,
            "--version",
            POWSHELL_VERSION,
            POWSHELL_PACKAGES,
        ],
        env=env,
        check=False,
    ).returncode != 0:
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
