#!/usr/bin/env python3
"""Stub-backed unit tests for the eight DevBox first-run installer payloads.

Each payload implements the installer CLI contract consumed by the orchestrator:
``id`` ``name`` ``depends`` ``meta`` and ``install``. These tests verify the
``id``/``name``/``depends``/``meta`` byte-exact contract and exercise ``install``
behavior with the external subprocess calls (``curl``/``bash``/``pip``/``venv``)
and the CA-bundle copy stubbed, so no network, no Python venv, and no real
runtime are required.

Run with::

    python3 -m unittest Common.tests.firstrun.test_firstrun_installers
    # or, from this directory:
    python3 test_firstrun_installers.py
    # or, if pytest is available:
    python3 -m pytest Common/tests/firstrun/test_firstrun_installers.py
"""
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # workspace root
FIRSTRUN_DIR = REPO / "Common" / "image" / "firstrun.d"

# (id, name, depends) pairs, matching each installer's meta output exactly.
EXPECTED = {
    "homebrew": ("10-homebrew.py", "homebrew", "Homebrew", ""),
    "fnm": ("15-fnm.py", "fnm", "Fast Node Manager", "homebrew"),
    "node-lts": ("16-node-lts.py", "node-lts", "Node LTS (via fnm)", "fnm"),
    "pi-agent-harness": ("20-pi-agent-harness.py", "pi-agent-harness", "Pi Agent Harness", "node-lts"),
    "copilot-cli": ("21-copilot-cli.py", "copilot-cli", "GitHub Copilot CLI", ""),
    "claude-code-cli": ("22-claude-code-cli.py", "claude-code-cli", "Claude Code CLI", ""),
    "aspire-cli": ("30-aspire-cli.py", "aspire-cli", "Aspire CLI", ""),
    "dotnet-lts": ("17-dotnet-lts.py", "dotnet-lts", ".NET SDK", ""),
    "powershell": ("18-powershell.py", "powershell", "PowerShell", "dotnet-lts"),
}


def _load(name):
    path = FIRSTRUN_DIR / name
    spec = importlib.util.spec_from_file_location("installer_" + name.replace("-", "_"), str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run_main(mod, argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = mod.main(list(argv))
    return rc, out.getvalue(), err.getvalue()


class _FakeProc:
    def __init__(self, returncode=0, stdout=""):
        self.returncode = returncode
        self.stdout = stdout


class _SubprocessStub:
    """A recording stand-in for subprocess.run.

    Returns ``_FakeProc(0)`` by default. The ``import certifi`` ``-c`` call
    returns the fixed certifi path as stdout. ``fail_on`` names command
    substrings that make subprocess.run return exit 1.
    """

    def __init__(self, fail_on=()):
        self.fail_on = tuple(fail_on)
        self.calls = []

    def __call__(self, cmd, env=None, **kwargs):
        self.calls.append((list(cmd), env, kwargs))
        joined = " ".join(cmd) if cmd else ""
        if any(tok in joined for tok in self.fail_on):
            return _FakeProc(returncode=1)
        if any("import certifi" in part for part in cmd if isinstance(part, str)):
            return _FakeProc(returncode=0, stdout="/home/test/certs/cert.pem\n")
        return _FakeProc(returncode=0)


def _patch_run(mod, fail_on=()):
    """Patch mod.subprocess.run with a recording stub; return (stub, unpatcher)."""
    stub = _SubprocessStub(fail_on=fail_on)
    unpatch = unittest.mock.patch.object(mod.subprocess, "run", stub)
    unpatch.start()
    return stub, unpatch


class MetaContractTests(unittest.TestCase):
    """The four introspection subcommands must be byte-exact."""

    def setUp(self):
        self.mods = {tid: _load(rel) for tid, (rel, mid, _, _) in EXPECTED.items()}

    def test_id(self):
        for tid, (rel, mid, _, _) in EXPECTED.items():
            rc, out, _ = _run_main(self.mods[tid], ["/x", "id"])
            self.assertEqual((rc, out), (0, mid + "\n"))

    def test_name(self):
        for tid, (rel, _, mname, _) in EXPECTED.items():
            rc, out, _ = _run_main(self.mods[tid], ["/x", "name"])
            self.assertEqual((rc, out), (0, mname + "\n"))

    def test_depends_has_no_trailing_newline(self):
        for tid, (rel, _, _, dep) in EXPECTED.items():
            rc, out, _ = _run_main(self.mods[tid], ["/x", "depends"])
            self.assertEqual(rc, 0)
            self.assertEqual(out, dep)

    def test_depends_values(self):
        for tid, (_, _, _, dep) in EXPECTED.items():
            self.assertEqual(_run_main(self.mods[tid], ["/x", "depends"])[1], dep)

    def test_meta_two_lines(self):
        for tid, (rel, mid, mname, _) in EXPECTED.items():
            rc, out, _ = _run_main(self.mods[tid], ["/x", "meta"])
            self.assertEqual(rc, 0)
            self.assertEqual(out, mid + "\n" + mname + "\n")

    def test_tool_object_attrs(self):
        for tid, (rel, mid, mname, _) in EXPECTED.items():
            self.assertEqual(self.mods[tid].TOOL_ID, mid)
            self.assertEqual(self.mods[tid].TOOL_NAME, mname)

    def test_no_arg_reports_usage_exit_1(self):
        for tid in EXPECTED:
            rc, out, err = _run_main(self.mods[tid], ["/x"])
            self.assertEqual(rc, 1)
            self.assertEqual(out, "")
            self.assertTrue(err.strip().startswith("Usage:"))

    def test_unknown_subcommand_exit_1(self):
        for tid in EXPECTED:
            rc, out, err = _run_main(self.mods[tid], ["/x", "bogus"])
            self.assertEqual(rc, 1)
            self.assertTrue(err.strip().startswith("Usage:"))


class HomebrewInstallTests(unittest.TestCase):
    def setUp(self):
        self.mod = _load("10-homebrew.py")

    def test_idempotent_when_brew_on_path(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: "/usr/bin/brew"):
            self.assertEqual(self.mod.install_tool(), 0)

    def test_sysroot_fallback_is_idempotent(self):
        # brew absent on PATH but present at the Linuxbrew sysroot: _has_brew
        # is True, so the installer returns 0 without invoking curl.
        stub, unpatch = _patch_run(self.mod)
        try:
            with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
                 unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: True):
                self.assertEqual(self.mod.install_tool(), 0)
        finally:
            unpatch.stop()
        # No curl download was attempted.
        self.assertTrue(not any(c[0] and c[0][0] == "curl" for c in stub.calls))

    def test_curl_failure_returns_1(self):
        # Simulate a first-time host (brew absent) so the installer reaches curl.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            stub, unpatch = _patch_run(self.mod, fail_on=["curl"])
            try:
                self.assertEqual(self.mod.install_tool(), 1)
            finally:
                unpatch.stop()

    def test_curl_then_bash_success(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            stub, unpatch = _patch_run(self.mod, fail_on=["__none__"])
            try:
                self.assertEqual(self.mod.install_tool(), 0)
            finally:
                unpatch.stop()

    def test_noninteractive_env_passed_to_installer(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            stub, unpatch = _patch_run(self.mod, fail_on=["__none__"])
            try:
                self.mod.install_tool()
            finally:
                unpatch.stop()
        bash_calls = [c for c in stub.calls if c[0] and c[0][0] == "bash"]
        self.assertTrue(bash_calls)
        env = bash_calls[0][1]
        self.assertIsInstance(env, dict)
        self.assertEqual(env.get("NONINTERACTIVE"), "1")


class FnmInstallTests(unittest.TestCase):
    def setUp(self):
        self.mod = _load("15-fnm.py")

    def test_idempotent_when_fnm_on_path(self):
        with unittest.mock.patch.object(
            self.mod.shutil, "which", lambda name: "/usr/bin/fnm" if name == "fnm" else None
        ):
            self.assertEqual(self.mod.install_tool(), 0)

    def test_brew_absent_returns_1_with_message(self):
        # brew absent on PATH AND at the Linuxbrew sysroot -> fnm errors.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            err = io.StringIO()
            with redirect_stderr(err):
                rc = self.mod.install_tool()
            self.assertEqual(rc, 1)
            self.assertIn("Homebrew is not installed", err.getvalue())

    def test_brew_install_success(self):
        # brew on PATH -> invoked by its resolved path (not the bare name); brew
        # install --no-ask fnm runs (no proceed-with-installation prompt).
        stub, unpatch = _patch_run(self.mod, fail_on=["__none__"])
        try:
            with unittest.mock.patch.object(
                self.mod.shutil, "which", lambda name: "/usr/bin/brew" if name == "brew" else None
            ):
                self.assertEqual(self.mod.install_tool(), 0)
        finally:
            unpatch.stop()
        self.assertTrue(
            any(
                len(c[0]) >= 3
                and os.path.basename(c[0][0]) == "brew"
                and "install" in c[0][1:]
                and "fnm" in c[0]
                and "--no-ask" in c[0]
                for c in stub.calls
            )
        )


def _patch_run_fnm(mod, fnm_dir=None, install_returncode=0):
    """Record subprocess.run for the fnm-backed installer.

    The ``fnm env --json`` call returns a JSON document whose ``FNM_DIR`` key is
    ``fnm_dir`` (default: a fresh temp dir that does not contain the pinned
    version, so the installer proceeds to install); the ``fnm install`` call
    returns ``install_returncode``. This exercises the real ``_resolve_fnm_dir``
    JSON parse rather than stubbing it out.
    """
    calls = []
    if fnm_dir is None:
        fnm_dir = str(Path(tempfile.mkdtemp()) / "fnm")

    def fake_run(cmd, env=None, **kwargs):
        calls.append((list(cmd), env, kwargs))
        joined = " ".join(cmd) if cmd else ""
        if "env" in joined and "--json" in joined:
            return _FakeProc(returncode=0, stdout=json.dumps({"FNM_DIR": fnm_dir}))
        return _FakeProc(returncode=install_returncode)

    patch = unittest.mock.patch.object(mod.subprocess, "run", fake_run)
    patch.start()
    return calls, patch


class NodeLtsInstallTests(unittest.TestCase):
    """The fnm-backed Node installer installs into the FNM_DIR fnm reports.

    ``fnm env --json`` is stubbed (fnm is not installed on the DevBox test host)
    to verify the value is parsed and handed to ``fnm install``; ``fnm`` is
    located via a PATH or Linuxbrew sysroot fallback. No real network/runtime is
    required.
    """

    def setUp(self):
        self.mod = _load("16-node-lts.py")

    # -- fnm discovery ------------------------------------------------------
    def test_fnm_executable_path_lookup(self):
        with unittest.mock.patch.object(
            self.mod.shutil, "which", lambda name: "/usr/bin/fnm" if name == "fnm" else None
        ):
            self.assertEqual(self.mod._fnm_executable(), "/usr/bin/fnm")

    def test_fnm_executable_sysroot_fallback(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: True):
            self.assertEqual(self.mod._fnm_executable(), self.mod.LINUXBREW_FNM)

    def test_fnm_executable_absent(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            self.assertIsNone(self.mod._fnm_executable())

    # -- FNM_DIR resolution (matches 30-fnm.sh) -----------------------------
    def test_resolve_fnm_dir_parses_json_and_expands(self):
        # fnm env --json emits FNM_DIR verbatim; ``~`` / ``$HOME`` are expanded.
        proc = _FakeProc(returncode=0, stdout='{"FNM_DIR":"${HOME}/custom-fnm"}')
        with unittest.mock.patch.object(self.mod.subprocess, "run", lambda *a, **k: proc):
            self.assertEqual(self.mod._resolve_fnm_dir("/x/fnm"), os.path.expanduser(os.path.expandvars("${HOME}/custom-fnm")))

    def test_resolve_fnm_dir_falls_back_on_bad_json(self):
        # Empty/invalid ``fnm env`` output (e.g. fnm errored) -> default, no crash.
        with unittest.mock.patch.object(self.mod.subprocess, "run", lambda *a, **k: _FakeProc(returncode=0, stdout="")):
            self.assertEqual(self.mod._resolve_fnm_dir("/x/fnm"), self.mod.FNM_DIR_DEFAULT)

    # -- install ------------------------------------------------------------
    def test_install_fnm_absent_returns_1_with_message(self):
        # fnm absent on PATH AND at the Linuxbrew sysroot -> errors.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: False):
            err = io.StringIO()
            with redirect_stderr(err):
                rc = self.mod.install_tool()
            self.assertEqual(rc, 1)
            self.assertIn("fnm is not installed", err.getvalue())

    def test_install_passes_fnm_dir_from_env_json(self):
        # Whatever ``FNM_DIR`` fnm env reports is parsed and handed to
        # ``fnm install`` via env; the pinned version is passed positionally.
        fnm_dir = "/home/bob/.local/share/fnm"  # confirmed via ``fnm env`` on the host
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: "/usr/bin/fnm"):
            calls, unpatch = _patch_run_fnm(self.mod, fnm_dir=fnm_dir)
            try:
                self.assertEqual(self.mod.install_tool(), 0)
            finally:
                unpatch.stop()
        install_calls = [c for c in calls if c[0] and "install" in c[0]]
        self.assertEqual(len(install_calls), 1)
        cmd, env, _ = install_calls[0]
        self.assertEqual(os.path.basename(cmd[0]), "fnm")
        self.assertEqual(cmd[1], "install")
        self.assertEqual(cmd[2], self.mod.NODE_VERSION)
        self.assertIsInstance(env, dict)
        self.assertEqual(env.get("FNM_DIR"), fnm_dir)

    def test_install_installs_pnpm_via_corepack(self):
        # After installing Node, pnpm is enabled via the fnm-installed node's
        # own corepack; both invocations carry FNM_DIR so the shim resolves
        # there. ``enable`` + ``prepare <spec> --activate`` must both run.
        fnm_dir = "/home/bob/.local/share/fnm"
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: "/usr/bin/fnm"):
            calls, unpatch = _patch_run_fnm(self.mod, fnm_dir=fnm_dir)
            try:
                self.assertEqual(self.mod.install_tool(), 0)
            finally:
                unpatch.stop()
        # Match by basename: the corepack arg is a full path, not bare "corepack".
        corepack_calls = [c for c in calls if c[0] and any(os.path.basename(a) == "corepack" for a in c[0])]
        self.assertEqual(len(corepack_calls), 2)
        self.assertEqual(os.path.basename(corepack_calls[0][0][0]), "corepack")
        self.assertEqual(corepack_calls[0][0][1], "enable")
        self.assertEqual(corepack_calls[1][0][1], "prepare")
        self.assertEqual(corepack_calls[1][0][2], "pnpm@" + self.mod.PNPM_SPEC)
        self.assertEqual(corepack_calls[1][0][3], "--activate")
        for _, env, _ in corepack_calls:
            self.assertIsInstance(env, dict)
            self.assertEqual(env.get("FNM_DIR"), fnm_dir)

    def test_install_failure_returns_1(self):
        # fnm present on PATH; ``fnm install`` returns non-zero -> install fails.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: "/usr/bin/fnm"):
            calls, unpatch = _patch_run_fnm(self.mod, install_returncode=1)
            try:
                self.assertEqual(self.mod.install_tool(), 1)
            finally:
                unpatch.stop()
        install_calls = [c for c in calls if c[0] and "install" in c[0]]
        self.assertEqual(len(install_calls), 1)

    def test_install_skip_when_already_installed(self):
        # Version dir already present under FNM_DIR -> install not attempted.
        home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        (home / "node-versions" / ("v" + self.mod.NODE_VERSION)).mkdir(parents=True)
        # fnm present at Linuxbrew sysroot; FNM_DIR from env json is `home`.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None), \
             unittest.mock.patch.object(self.mod.os, "access", lambda *a, **k: True):
            calls, unpatch = _patch_run_fnm(self.mod, fnm_dir=str(home))
            try:
                self.assertEqual(self.mod.install_tool(), 0)
            finally:
                unpatch.stop()
        install_calls = [c for c in calls if c[0] and "install" in c[0]]
        self.assertEqual(install_calls, [])

    def test_no_arg_reports_usage_exit_1(self):
        err = io.StringIO()
        with redirect_stderr(err):
            rc = self.mod.main(["/x"])
        self.assertEqual(rc, 1)
        self.assertTrue(err.getvalue().strip().startswith("Usage:"))

    def test_unknown_subcommand_exit_1(self):
        err = io.StringIO()
        with redirect_stderr(err):
            rc = self.mod.main(["/x", "bogus"])
        self.assertEqual(rc, 1)
        self.assertTrue(err.getvalue().strip().startswith("Usage:"))


class AspireInstallTests(unittest.TestCase):
    def setUp(self):
        self.mod = _load("30-aspire-cli.py")

    def test_idempotent_when_aspire_on_path(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: "/usr/bin/aspire"):
            self.assertEqual(self.mod.install_tool(), 0)

    def test_curl_failure_returns_1(self):
        # Simulate aspire absent on PATH so the installer reaches curl.
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None):
            stub, unpatch = _patch_run(self.mod, fail_on=["curl"])
            try:
                self.assertEqual(self.mod.install_tool(), 1)
            finally:
                unpatch.stop()

    def test_curl_then_bash_success(self):
        with unittest.mock.patch.object(self.mod.shutil, "which", lambda name: None):
            stub, unpatch = _patch_run(self.mod, fail_on=["__none__"])
            try:
                self.assertEqual(self.mod.install_tool(), 0)
            finally:
                unpatch.stop()


class DotnetLtsInstallTests(unittest.TestCase):
    """The .NET installer downloads dotnet-install.sh and installs the LTS channel
    to ${HOME}/.dotnet; idempotent once ``dotnet`` is already present."""

    def setUp(self):
        # HOME-relative install root lands under a temp dir (no host writes).
        self.tmp = Path(tempfile.mkdtemp())
        self._old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.tmp)
        self.submod = _load("17-dotnet-lts.py")

    def tearDown(self):
        os.environ.pop("HOME", None)
        if self._old_home is not None:
            os.environ["HOME"] = self._old_home
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _install(self, fail_on=()):
        stub, unpatch = _patch_run(self.submod, fail_on=fail_on)
        try:
            rc = self.submod.install_tool()
        finally:
            unpatch.stop()
        return rc, stub.calls

    def test_curl_failure_returns_1(self):
        rc, calls = self._install(fail_on=["curl"])
        self.assertEqual(rc, 1)
        self.assertTrue(any(c[0] and os.path.basename(c[0][0]) == "curl" for c in calls))

    def test_curl_then_install_success(self):
        rc, calls = self._install(fail_on=["__none__"])
        self.assertEqual(rc, 0)

    def test_install_channel_and_target(self):
        _, calls = self._install(fail_on=["__none__"])
        install_calls = [c for c in calls if c[0] and "--channel" in c[0]]
        self.assertEqual(len(install_calls), 1)
        cmd = install_calls[0][0]
        self.assertEqual(cmd[1], "--channel")
        self.assertEqual(cmd[2], self.submod.DOTNET_CHANNEL)
        self.assertEqual(cmd[3], "--install-dir")
        self.assertEqual(cmd[4], self.submod.DOTNET_HOME)

    def test_idempotent_when_sdk_present(self):
        # ``dotnet`` already under DOTNET_HOME -> no curl download attempted.
        os.makedirs(self.submod.DOTNET_HOME, exist_ok=True)
        open(self.submod.DOTNET_EXE, "w").close()
        rc, calls = self._install(fail_on=["__none__"])
        self.assertEqual(rc, 0)
        self.assertTrue(not any(c[0] and os.path.basename(c[0][0]) == "curl" for c in calls))


class PowershellInstallTests(unittest.TestCase):
    """PowerShell is installed as a dotnet global tool into ${HOME}/.pwsh and
    depends on the .NET SDK (``dotnet-lts``)."""

    def setUp(self):
        # HOME-relative install root lands under a temp dir (no host writes).
        self.tmp = Path(tempfile.mkdtemp())
        self._old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.tmp)
        self.submod = _load("18-powershell.py")

    def tearDown(self):
        os.environ.pop("HOME", None)
        if self._old_home is not None:
            os.environ["HOME"] = self._old_home
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _install(self, fail_on=()):
        stub, unpatch = _patch_run(self.submod, fail_on=fail_on)
        try:
            rc = self.submod.install_tool()
        finally:
            unpatch.stop()
        return rc, stub.calls

    def test_depends_is_dotnet_lts(self):
        self.assertEqual(self.submod.DEPENDS, "dotnet-lts")

    def test_dotnet_absent_returns_1_with_message(self):
        # SDK missing -> informative error, no dotnet invocation.
        err = io.StringIO()
        with redirect_stderr(err):
            rc, calls = self._install(fail_on=["__none__"])
        self.assertEqual(rc, 1)
        self.assertIn(".NET SDK (dotnet-lts) is not installed", err.getvalue())
        self.assertTrue(not any(c[0] and c[0][0] == str(self.submod.DOTNET_EXE) for c in calls))

    def test_pwsh_installed_via_dotnet_tool(self):
        # SDK present -> ``dotnet tool install`` runs against ${HOME}/.pwsh.
        os.makedirs(self.submod.DOTNET_HOME, exist_ok=True)
        open(self.submod.DOTNET_EXE, "w").close()
        rc, calls = self._install(fail_on=["__none__"])
        self.assertEqual(rc, 0)
        tool_calls = [c for c in calls if c[0] and c[0][0] == str(self.submod.DOTNET_EXE)]
        self.assertEqual(len(tool_calls), 1)
        cmd, env, _ = tool_calls[0]
        self.assertEqual(cmd[1:5], ["tool", "install", "--tool-path", str(self.submod.POWSHELL_HOME)])
        # The pinned tool version is passed before the package name.
        self.assertEqual(cmd[5:7], ["--version", self.submod.POWSHELL_VERSION])
        self.assertEqual(cmd[7], self.submod.POWSHELL_PACKAGES)
        self.assertIsInstance(env, dict)
        self.assertEqual(env.get("DOTNET_ROOT"), self.submod.DOTNET_HOME)

    def test_idempotent_when_pwsh_present(self):
        # pwsh already under POWSHELL_HOME -> no dotnet tool install attempted.
        os.makedirs(self.submod.POWSHELL_HOME, exist_ok=True)
        open(self.submod.POWSHELL_EXE, "w").close()
        rc, calls = self._install(fail_on=["__none__"])
        self.assertEqual(rc, 0)
        self.assertTrue(not any(c[0] and c[0][0] == str(self.submod.DOTNET_EXE) for c in calls))


class _VenvInstallerCase(unittest.TestCase):
    """Shared fixture for the 20/21/22 venv+certifi+wrapper installers.

    External subprocess calls (venv/pip/certifi.where/curl/bash/npm) are stubbed,
    and the CA-bundle copy is stubbed to a recorder (the fake certifi path's
    parent directory does not exist on the test host). A real temp HOME lets the
    wrapper be written to disk and asserted on.
    """

    SUBFILE = None
    WRAPPER_NAME = None  # set per subclass

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self._old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.tmp)
        self.venv = self.tmp / "venv"
        self.venv.mkdir()  # real dir -> install_tool skips venv creation
        self.submod = _load(self.SUBFILE)

    def tearDown(self):
        os.environ.pop("HOME", None)
        if self._old_home is not None:
            os.environ["HOME"] = self._old_home
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _install(self, access):
        """Run install under stubs. Returns (rc, calls, copy_instance, wrapper_text)."""
        stub = _SubprocessStub(fail_on=["__none__"])
        unpatch_run = unittest.mock.patch.object(self.submod.subprocess, "run", stub)
        unpatch_run.start()
        copy_instance = {}

        class _CopyStub:
            def __call__(self, src, dst):
                copy_instance["src"] = src
                copy_instance["dst"] = dst

        unpatch_copy = unittest.mock.patch.object(
            self.submod.shutil, "copyfile", _CopyStub()
        )
        unpatch_copy.start()
        unpatch_access = unittest.mock.patch.object(
            self.submod.os, "access", lambda p, m=0: access
        )
        unpatch_access.start()
        try:
            rc = self.submod.install_tool()
        finally:
            unpatch_access.stop()
            unpatch_copy.stop()
            unpatch_run.stop()
        wrapper = self.tmp / "bin" / self.WRAPPER_NAME
        text = wrapper.read_text() if wrapper.exists() else None
        return rc, stub.calls, copy_instance, text


class PiInstallTests(_VenvInstallerCase):
    SUBFILE = "20-pi-agent-harness.py"
    WRAPPER_NAME = "pi"

    def test_install_returns_0_and_creates_wrapper(self):
        rc, calls, _, text = self._install(access=True)
        self.assertEqual(rc, 0)
        self.assertIsNotNone(text)
        self.assertIn('export VIRTUAL_ENV="${HOME}/pi-venv"', text)
        self.assertIn('exec "${HOME}/.local/bin/pi" "$@"', text)
        # venv + pip + certifi.where were invoked.
        self.assertTrue(any("venv" in " ".join(c[0]) for c in calls))
        self.assertTrue(any("pip" in " ".join(c[0]) for c in calls))

    def test_npm_invoked_when_binary_absent(self):
        # `pi` absent (os.access False) -> npm install attempted; the stubbed
        # install never produces the binary, so install returns 1. npm is now
        # resolved explicitly (prefer it on PATH), so stub ``shutil.which`` to
        # resolve npm rather than leaving it absent.
        with unittest.mock.patch.object(
            self.submod.shutil, "which", lambda name: "/opt/fake/bin/npm" if name == "npm" else None
        ):
            rc, calls, _, _ = self._install(access=False)
        self.assertEqual(rc, 1)
        self.assertTrue(any(c[0] and c[0][0].endswith("npm") for c in calls))

    def test_npm_invoked_with_node_bin_prepended_to_path(self):
        # npm (a ``#!/usr/bin/env node`` wrapper) is exec'd by absolute path, so
        # ``env`` re-looks-up ``node`` on PATH. The non-login install subprocess
        # has no login profile yet, so the Node bin dir (node + npm share it)
        # must be the first PATH entry on the npm invocation.
        with unittest.mock.patch.object(
            self.submod.shutil, "which", lambda name: "/opt/fake/bin/npm" if name == "npm" else None
        ):
            rc, calls, _, _ = self._install(access=False)
        self.assertEqual(rc, 1)  # stubbed install never produces the binary
        npm_call = next(c for c in calls if c[0] and c[0][0].endswith("npm"))
        self.assertEqual(npm_call[1]["PATH"].split(os.pathsep)[0], "/opt/fake/bin")

    def test_npm_unavailable_returns_1_without_crashing(self):
        # Regression for the firstrun ``npm`` lookup: the orchestrator runs
        # ``install`` in a non-login shell, so the login profile hooks that put
        # npm on PATH have not run. When npm cannot be resolved here it must
        # fail cleanly (rc 1, a message) -- never crash on a bare ``npm``
        # lookup. ``shutil.which`` returns nothing and there is no fnm dir.
        with unittest.mock.patch.object(self.submod.shutil, "which", lambda name: None):
            rc, calls, _, _ = self._install(access=False)
        self.assertEqual(rc, 1)
        self.assertFalse(any(c[0] and c[0][0].endswith("npm") for c in calls))

    def _patch_fnm_env(self, fnm_json):
        """Return a (shutil.which, subprocess.run) patch pair for _resolve_npm.

        ``shutil.which("npm")`` returns None so the fnm branch is exercised,
        while ``shutil.which("fnm")`` resolves a runnable fnm (so
        ``_fnm_env`` actually runs the stubbed ``fnm env --json``); a single
        ``fnm env --json`` invocation is stubbed to ``fnm_json``."""
        which = unittest.mock.patch.object(
            self.submod.shutil, "which", lambda name: "/usr/bin/fnm" if name == "fnm" else None
        )
        run = unittest.mock.patch.object(
            self.submod.subprocess, "run",
            lambda *a, **k: _FakeProc(returncode=0, stdout=fnm_json),
        )
        return which, run

    def test_resolve_npm_prefers_fnm_multisHELL_path(self):
        # ``fnm env --json`` reports the active node's bin as
        # ``FNM_MULTISHELL_PATH``; _resolve_npm must prefer it over a plain
        # node-versions glob of an *inactive* version.
        home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        active = home / "node-versions" / "v26.13.1" / "bin"
        inactive = home / "node-versions" / "v22.0.0" / "bin"
        for d in (active, inactive):
            d.mkdir(parents=True)
        for f in (active / "npm", inactive / "npm"):
            f.write_text("#!sh\n")
            os.chmod(f, 0o755)
        env_json = json.dumps({
            "FNM_DIR": str(home),
            "FNM_MULTISHELL_PATH": str(active),
        })
        which, run = self._patch_fnm_env(env_json)
        with which, run:
            resolved = self.submod._resolve_npm()
        self.assertEqual(resolved, os.path.join(str(active), "npm"))

    def test_resolve_npm_multisHELL_points_at_node_root(self):
        # fnm v2: ``FNM_MULTISHELL_PATH`` is the multisHELL symlink resolving to
        # the active version *root* (``.../installation``); npm lives at
        # ``<root>/bin/npm``, not ``<root>/npm``. Must append ``/bin/npm``.
        home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        node_root = home / "installation"
        active_bin = node_root / "bin"
        active_bin.mkdir(parents=True)
        npm = active_bin / "npm"
        npm.write_text("#!sh\n")
        os.chmod(npm, 0o755)
        env_json = json.dumps({
            "FNM_DIR": str(home),
            "FNM_MULTISHELL_PATH": str(node_root),
        })
        which, run = self._patch_fnm_env(env_json)
        with which, run:
            resolved = self.submod._resolve_npm()
        self.assertEqual(resolved, os.path.join(str(active_bin), "npm"))

    def test_resolve_npm_falls_back_to_version_glob(self):
        # Older fnm emits no ``FNM_MULTISHELL_PATH``: fall back to the newest
        # ``FNM_DIR/node-versions/*/bin/npm``.
        home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        for ver in ("v22.0.0", "v26.13.1"):
            (home / "node-versions" / ver / "bin").mkdir(parents=True)
            npm = home / "node-versions" / ver / "bin" / "npm"
            npm.write_text("#!sh\n")
            os.chmod(npm, 0o755)
        which, run = self._patch_fnm_env(json.dumps({"FNM_DIR": str(home)}))
        with which, run:
            resolved = self.submod._resolve_npm()
        self.assertEqual(
            resolved, os.path.join(str(home / "node-versions" / "v26.13.1" / "bin"), "npm")
        )

    def test_resolve_npm_prefers_path_npm(self):
        # An npm already resolvable on PATH wins over fnm's active node.
        env_json = json.dumps({
            "FNM_DIR": "/home/test/.fnm",
            "FNM_MULTISHELL_PATH": "/home/test/.fnm/node-versions/v26.13.1/bin",
        })
        which = unittest.mock.patch.object(
            self.submod.shutil, "which", lambda name: "/opt/node/bin/npm" if name == "npm" else None
        )
        run = unittest.mock.patch.object(self.submod.subprocess, "run", lambda *a, **k: _FakeProc(returncode=0, stdout=env_json))
        with which, run:
            resolved = self.submod._resolve_npm()
        self.assertEqual(resolved, "/opt/node/bin/npm")


class CopilotInstallTests(_VenvInstallerCase):
    SUBFILE = "21-copilot-cli.py"
    WRAPPER_NAME = "copilot"

    def test_install_returns_0_and_creates_wrapper(self):
        rc, calls, _, text = self._install(access=True)
        self.assertEqual(rc, 0)
        self.assertIsNotNone(text)
        self.assertIn('export VIRTUAL_ENV="${HOME}/copilot-venv"', text)
        self.assertIn('exec "${HOME}/.local/bin/copilot" "$@"', text)

    def test_certifi_and_ca_used(self):
        _, calls, copy_instance, _ = self._install(access=True)
        self.assertEqual(copy_instance.get("src"), "/etc/ssl/certs/ca-certificates.crt")
        self.assertEqual(copy_instance.get("dst"), "/home/test/certs/cert.pem")
        self.assertTrue(any("import certifi" in " ".join(c[0]) for c in calls))


class ClaudeInstallTests(_VenvInstallerCase):
    SUBFILE = "22-claude-code-cli.py"
    WRAPPER_NAME = "claude"

    def test_install_returns_0_and_creates_wrapper(self):
        rc, calls, _, text = self._install(access=True)
        self.assertEqual(rc, 0)
        self.assertIsNotNone(text)
        self.assertIn('export VIRTUAL_ENV="${HOME}/claude-venv"', text)
        self.assertIn('exec "${HOME}/.local/bin/claude" "$@"', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
