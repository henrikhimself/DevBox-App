#!/usr/bin/env python3
"""Claude Code CLI first-run installer."""
import os
import shutil
import subprocess
import sys
import tempfile

TOOL_ID = "claude-code-cli"
TOOL_NAME = "Claude Code CLI"
DEPENDS = ""

CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
INSTALL_URL = "https://claude.ai/install.sh"

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])

WRAPPER = '''#!/usr/bin/env sh
# Wrapper that runs the Claude Code CLI with the devbox Python venv active.
# ~/bin is first in PATH, so this shadows the real binary.
export VIRTUAL_ENV="${HOME}/claude-venv"
export PATH="${VIRTUAL_ENV}/bin:${PATH}"
exec "${HOME}/.local/bin/claude" "$@"
'''


def _path(home, *parts):
    return os.path.join(home, *parts)


def _write_wrapper(home):
    bin_dir = _path(home, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    wrapper = _path(home, "bin", "claude")
    with open(wrapper, "w") as fh:
        fh.write(WRAPPER)
    os.chmod(wrapper, 0o755)


def _venv_python(venv_dir):
    return _path(venv_dir, "bin", "python")


def _download_installer(url):
    fd, installer = tempfile.mkstemp(prefix="claude-install-")
    os.close(fd)
    try:
        if subprocess.run(
            ["curl", "-fsSL", url, "-o", installer]
        ).returncode != 0:
            os.unlink(installer)
            return None
        if subprocess.run(["bash", installer]).returncode != 0:
            os.unlink(installer)
            return None
    finally:
        os.unlink(installer)
    return True


def install_tool():
    home = os.environ["HOME"]
    venv_dir = _path(home, "claude-venv")
    claude_bin = _path(home, ".local", "bin", "claude")

    if not os.path.isdir(venv_dir):
        if subprocess.run(["python3", "-m", "venv", venv_dir]).returncode != 0:
            return 1

    venv_py = _venv_python(venv_dir)
    if subprocess.run(
        [venv_py, "-m", "pip", "install", "--upgrade", "pip", "certifi"]
    ).returncode != 0:
        return 1

    proc = subprocess.run(
        [venv_py, "-c", "import certifi; print(certifi.where())"],
        stdout=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        return 1
    certifi_path = proc.stdout.strip()

    try:
        shutil.copyfile(CA_BUNDLE, certifi_path)
    except OSError:
        return 1

    if not os.access(claude_bin, os.X_OK) and not _download_installer(INSTALL_URL):
        print(
            "Claude Code install did not produce an executable at {0}.".format(
                claude_bin
            ),
            file=sys.stderr,
        )
        return 1

    _write_wrapper(home)
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
