#!/usr/bin/env python3
"""Pi Agent Harness first-run installer.

Depends on: node-lts

The harness packages itself with ``npm install -g``; Node (and its bundled npm)
only ships from ``node-lts`` -- the base image has no npm. Declaring the
dependency lets the orchestrator install Node first.
"""
import json
import os
import shutil
import subprocess
import sys

TOOL_ID = "pi-agent-harness"
TOOL_NAME = "Pi Agent Harness"
DEPENDS = "node-lts"

CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
NPM_PACKAGE = "@earendil-works/pi-coding-agent"

# fnm is not on PATH during first-run (mirroring 16-node-lts.py), so resolve it
# explicitly rather than relying on a bare ``npm`` lookup: node-lts installs the
# Node whose bundled npm we need into FNM_DIR, but node-lts only puts that Node
# on PATH at *login* (profile.d/20-fnm.sh + 30-node.sh), which the orchestrator's
# non-login ``install`` subprocess never runs.
FNM_DIR_DEFAULT = os.path.expanduser(os.path.expandvars("${HOME}/.fnm"))
LINUXBREW_FNMBIN = "/home/linuxbrew/.linuxbrew/bin/fnm"

USAGE = "Usage: {0} <id|name|depends|meta|install>".format(sys.argv[0])

WRAPPER = '''#!/usr/bin/env sh
# Wrapper that runs the pi agent harness with the devbox Python venv active.
# ~/bin is first in PATH, so this shadows the real binary.
export VIRTUAL_ENV="${HOME}/pi-venv"
export PATH="${VIRTUAL_ENV}/bin:${PATH}"
exec "${HOME}/.local/bin/pi" "$@"
'''


def _path(home, *parts):
    return os.path.join(home, *parts)


def _write_wrapper(home):
    bin_dir = _path(home, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    wrapper = _path(home, "bin", "pi")
    with open(wrapper, "w") as fh:
        fh.write(WRAPPER)
    os.chmod(wrapper, 0o755)


def _fnm_executable():
    """Locate a runnable ``fnm``: prefer a PATH lookup, then the Linuxbrew
    sysroot ``/home/linuxbrew/.linuxbrew/bin/fnm`` (Linux only).

    fnm is not on PATH during first-run, so callers must use the returned full
    path rather than the bare name ``"fnm"`` (mirroring ``16-node-lts.py``).
    Returns ``None`` when fnm cannot be found."""
    found = shutil.which("fnm")
    if found is not None:
        return found
    return LINUXBREW_FNMBIN if os.access(LINUXBREW_FNMBIN, os.X_OK) else None


def _fnm_env():
    """Run ``fnm env --json`` once and return the parsed mapping.

    fnm's ``env --json`` is the shell-independent single source of truth for
    how it would arrange a login shell: ``FNM_DIR`` (where versions live) and,
    crucially, ``FNM_MULTISHELL_PATH`` (fnm's *active* Node version marker --
    fnm v2 points it at the active version *root*, and a login shell prepends
    ``<FNM_MULTISHELL_PATH>/bin`` to ``PATH``; older fnm points it at the
    ``bin`` dir directly). Parsing
    it avoids assuming ``FNM_DIR``'s default (users may override it) and avoids
    the orchestrator's non-login ``install`` subprocess ever needing
    ``20-fnm.sh``. Returns ``{"FNM_DIR": FNM_DIR_DEFAULT}`` when fnm is
    unavailable or its output cannot be parsed, so callers can still fall back
    to scanning ``FNM_DIR/node-versions`` (an older fnm that emits no
    ``FNM_MULTISHELL_PATH`` under a single installed version)."""
    fnm = _fnm_executable()
    if fnm is None:
        return {"FNM_DIR": FNM_DIR_DEFAULT}
    try:
        proc = subprocess.run(
            [fnm, "env", "--json"], capture_output=True, text=True, check=True
        )
        value = json.loads(proc.stdout)
    except (subprocess.CalledProcessError, ValueError):
        return {"FNM_DIR": FNM_DIR_DEFAULT}
    if not isinstance(value, dict):
        return {"FNM_DIR": FNM_DIR_DEFAULT}
    value.setdefault("FNM_DIR", FNM_DIR_DEFAULT)
    return value


def _bin_with_npm(root):
    """Return ``<base>/npm`` for the first ``base`` in ``(root, root/bin)`` that
    holds a runnable Node ``npm``, else ``None``.

    fnm's ``FNM_MULTISHELL_PATH`` points either at the active version's ``bin``
    directory (older fnm) or at the active version *root*, whose binaries live
    under ``<root>/bin`` (fnm v2: the multisHELL symlink resolves to
    ``<FNM_DIR>/node-versions/<ver>/installation``, so ``<root>/bin/npm`` is the
    working path). Trying ``root`` then ``root/bin`` covers both. ``os.access`` (X_OK) also rejects fnm layout variants with no bundled npm (npm is bundled
    into the Node build, so it is not always present as ``bin/npm``)."""
    for base in (root, os.path.join(root, "bin")):
        npm_path = os.path.join(base, "npm")
        if os.access(npm_path, os.X_OK):
            return npm_path
    return None


def _resolve_npm():
    """Return an absolute path to a runnable ``npm``, or ``None``.

    ``DEPENDS = \"node-lts\"`` guarantees Node is *installed* into fnm's
    ``FNM_DIR`` before this runs, but nothing puts that Node -- and its bundled
    npm -- on ``PATH`` in the orchestrator's non-login ``install`` subprocess
    (the login profile hooks ``20-fnm.sh`` / ``30-node.sh`` never run). Resolve
    npm explicitly, in order:

    1. ``npm`` already resolvable on ``PATH`` (e.g. a non-fnm Node install);
    2. the active Node version reported by ``fnm env --json`` -- its
       ``FNM_MULTISHELL_PATH`` (resolved against the active version's ``bin``
       dir, fnm v2 appends ``/bin``) is what fnm prepends to ``PATH`` at login,
       so this is preferred over a version glob;
    3. a last-resort scan of ``FNM_DIR/node-versions/*/`` (newest wins),
       checking both ``<version>/installation/bin/npm`` and
       ``<version>/bin/npm`` to cover fnm's different version layouts, and an
       older fnm that emits no ``FNM_MULTISHELL_PATH``.
    """
    npm = shutil.which("npm")
    if npm:
        return npm

    env = _fnm_env()
    for root_key in ("FNM_MULTISHELL_PATH", "FNM_DIR"):
        root_raw = env.get(root_key)
        if not root_raw:
            continue
        root = os.path.expanduser(os.path.expandvars(root_raw))
        if root_key == "FNM_MULTISHELL_PATH":
            # fnm's multisHELL path: active version root or its bin dir.
            candidates = [root]
        else:
            versions = os.path.join(root, "node-versions")
            if os.path.isdir(versions):
                names = [d for d in os.listdir(versions) if d.startswith("v")]
                names.sort()
                # fnm v2 stores binaries under <version>/installation/bin;
                # older layouts place them under <version>/bin.
                candidates = [
                    os.path.join(versions, name, seg)
                    for name in reversed(names)
                    for seg in ("installation/bin", "bin")
                ]
            else:
                continue
        for bin_dir in candidates:
            npm_path = _bin_with_npm(bin_dir)
            if npm_path:
                return npm_path
    return None


def _venv_python(venv_dir):
    return _path(venv_dir, "bin", "python")


def install_tool():
    home = os.environ["HOME"]
    venv_dir = _path(home, "pi-venv")
    pi_bin = _path(home, ".local", "bin", "pi")
    pi_dir = _path(home, ".pi", "agent")
    npm_prefix = _path(home, ".local")

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

    if not os.access(pi_bin, os.X_OK):
        npm = _resolve_npm()
        if npm is None:
            print(
                "Node runtime not found (node/npm absent from PATH and not "
                "installed via node-lts); install a Node runtime before "
                "installing the pi agent harness.",
                file=sys.stderr,
            )
            return 1

        # npm here is a wrapper whose first line is ``#!/usr/bin/env node``:
        # exec'ing it by absolute path makes ``env`` re-lookup ``node`` on
        # PATH. The orchestrator runs ``install`` in a non-login subprocess, so
        # the login profile (20-fnm.sh / 30-node.sh) has not put the Node bin
        # dir on PATH yet. Derive it from the resolved npm path (npm and node
        # share one ``bin`` -- fnm v2's ``FNM_MULTISHELL_PATH`` points at the
        # version root, so _resolve_npm returns ``.../installation/bin/npm``,
        # whose dirname is the exact dir fnm prepends at login) and prepend it
        # to the subprocess PATH so ``node`` -- and thus npm itself -- resolves.
        node_bin = os.path.dirname(npm)
        env = dict(os.environ, PATH=os.pathsep.join([node_bin, os.environ.get("PATH", "")]))
        subprocess.run(
            [
                npm, "install", "-g", "--ignore-scripts",
                "--min-release-age=0", "--prefix", npm_prefix, NPM_PACKAGE,
            ],
            env=env,
        )

    os.makedirs(pi_dir, exist_ok=True)

    if not os.access(pi_bin, os.X_OK):
        print(
            "Pi agent harness install did not produce an executable at {0}.".format(
                pi_bin
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
