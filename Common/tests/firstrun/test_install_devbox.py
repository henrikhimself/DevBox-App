#!/usr/bin/env python3
"""Stub-backed unit tests for the DevBox first-run orchestrator.

These exercise the orchestrator's pure functions and subprocess-facing
functions (via fake installer stub scripts) without a TTY or the real runtime.
Run with::

    python3 -m unittest Common.tests.firstrun.test_install_devbox
    # or, from this directory:
    python3 test_install_devbox.py
"""
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]  # workspace root
ORCHESTRATOR_PATH = REPO / "Common" / "image" / "script" / "install-devbox.py"
SHIM_PATH = REPO / "Common" / "image" / "profile.d" / "50-install-devbox.sh"

_spec = importlib.util.spec_from_file_location("devbox_install", str(ORCHESTRATOR_PATH))
orch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(orch)

# ids used by the real installers, in presentation (filename) order.
REAL_IDS = ["homebrew", "fnm", "pi-agent-harness", "copilot-cli", "claude-code-cli", "aspire-cli"]
REAL_DEPS = {"fnm": ["homebrew"]}


def _collect_prompt_sink():
    out = []

    def sink(msg):
        out.append(msg)

    return out, sink


class SelectionParsingTests(unittest.TestCase):
    def setUp(self):
        self.ids = ["homebrew", "fnm", "aspire-cli"]
        self.id_to_index = {"homebrew": 0, "fnm": 1, "aspire-cli": 2}

    def _parse(self, line):
        return orch.parse_selection(line, self.ids, self.id_to_index)

    def test_empty_is_all(self):
        mode, selected = self._parse("")
        self.assertEqual(mode, "all")
        self.assertEqual(selected, {0, 1, 2})

    def test_all_keyword(self):
        mode, selected = self._parse("all")
        self.assertEqual(mode, "all")

    def test_none_skip_zero_are_skip(self):
        for line in ("none", "skip", "0"):
            mode, selected = self._parse(line)
            self.assertEqual(mode, "skip", line)
            self.assertEqual(selected, set())

    def test_uppercase_all_and_none(self):
        self.assertEqual(self._parse("ALL")[0], "all")
        self.assertEqual(self._parse("NONE")[0], "skip")

    def test_single_number(self):
        self.assertEqual(self._parse("1"), ("ok", {0}))
        self.assertEqual(self._parse("3"), ("ok", {2}))

    def test_single_id(self):
        self.assertEqual(self._parse("fnm"), ("ok", {1}))

    def test_commas_and_spaces_mixed(self):
        self.assertEqual(self._parse("1,2"), ("ok", {0, 1}))
        self.assertEqual(self._parse(" 2 , aspire-cli"), ("ok", {1, 2}))
        self.assertEqual(self._parse("3 1"), ("ok", {0, 2}))

    def test_invalid_keyword(self):
        for line in ("garbage", "1 9", "abc 1"):
            self.assertEqual(self._parse(line), ("invalid", set()), line)

    def test_zero_is_skip_not_all(self):
        # bash treats 0 as skip (all-zero index would be 1, out of range).
        self.assertEqual(self._parse("0"), ("skip", set()))

    def test_out_of_range_number(self):
        self.assertEqual(self._parse("9"), ("invalid", set()))
        self.assertEqual(self._parse("4"), ("invalid", set()))

    def test_whitespace_only_is_invalid_not_all(self):
        # Mirrors bash: whitespace-only input word-splits to no tokens -> invalid.
        self.assertEqual(self._parse("   "), ("invalid", set()))


class SelectIndicesLoopTests(unittest.TestCase):
    def setUp(self):
        self.ids = ["homebrew", "fnm", "aspire-cli"]
        self.id_to_index = {"homebrew": 0, "fnm": 1, "aspire-cli": 2}

    def test_re_prompts_then_accepts(self):
        prompts, sink = _collect_prompt_sink()
        indices, skip = orch.select_indices(
            self.ids, self.id_to_index, ["garbage", "0"], sink
        )
        self.assertEqual((indices, skip), ([], True))
        self.assertEqual(len(prompts), 2)  # prompt written before each attempt

    def test_eof_is_install_all(self):
        prompts, sink = _collect_prompt_sink()
        indices, skip = orch.select_indices(self.ids, self.id_to_index, [], sink)
        self.assertEqual((indices, skip), ([0, 1, 2], False))

    def test_prompt_goes_to_sink_not_stdout(self):
        buf = io.StringIO()
        indices, _ = orch.select_indices(
            self.ids, self.id_to_index, ["1"], buf.write
        )
        self.assertEqual((indices, False), ([0], False))
        self.assertEqual(buf.getvalue(), "Install selection [all]: ")


class ClosureTests(unittest.TestCase):
    def test_transitive_closure(self):
        deps = {"a": ["b"], "b": ["c"], "c": [], "d": []}
        self.assertEqual(orch.transitive_closure({"a"}, deps), {"a", "b", "c"})

    def test_closure_ignores_unknown_deps(self):
        deps = {"fnm": ["homebrew"]}
        self.assertEqual(orch.transitive_closure({"fnm"}, deps), {"fnm", "homebrew"})


class OrderingTests(unittest.TestCase):
    """Installation order is depends-driven; presentation order is filename order.
    The two axes are decoupled."""

    def _ordered(self, ids, deps, selected):
        # selected is a list of indices into ids (as the orchestrator expects).
        return orch.ordered_targets(ids, deps, selected)

    def test_selecting_fnm_forces_homebrew(self):
        self.assertEqual(
            self._ordered(REAL_IDS, REAL_DEPS, [1]), ["homebrew", "fnm"]
        )

    def test_install_all_matches_filename_order(self):
        # Bash installed in filename order; the chosen tie-break reproduces it.
        self.assertEqual(
            self._ordered(REAL_IDS, REAL_DEPS, list(range(len(REAL_IDS)))),
            REAL_IDS,
        )

    def test_dependency_defers_dependent_past_filename_position(self):
        # zebra (filename rank 0) depends on apple (rank 1): apple installs first.
        ids = ["zebra", "apple", "banana"]
        deps = {"zebra": ["apple"]}
        # install order is NOT filename order (zebra deferred):
        self.assertEqual(self._ordered(ids, deps, [0, 1, 2]), ["apple", "banana", "zebra"])

    def test_presentation_is_filename_sorted_independent_of_install(self):
        ids = ["zebra", "apple", "banana"]  # intentionally unsorted ids
        deps = {"zebra": ["apple"]}
        # presentation/menu order is the sorted-filename order:
        self.assertEqual(list(ids), ["zebra", "apple", "banana"])
        # install order (filename tie-break, depends override) differs from it:
        self.assertEqual(self._ordered(ids, deps, [0, 1, 2]), ["apple", "banana", "zebra"])

    def test_cycle_is_detected(self):
        ids = ["a", "b"]
        deps = {"a": ["b"], "b": ["a"]}
        with self.assertRaises(orch.DependencyCycleError):
            orch.ordered_targets(ids, deps, [0, 1])


def _make_stub(directory, name, meta, depends, install_return_code=0):
    """Create a fake installer stub script (*.py) in ``directory``.

    The stub implements the real installer CLI contract: ``meta`` prints the id
    and name on two lines, ``depends`` prints the space-separated deps, and
    ``install`` exits with ``install_return_code``.
    """
    path = Path(directory) / name
    meta_a, meta_b = meta
    body = (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        'if sys.argv[1] == "meta":\n'
        '    print(%r)\n'
        '    print(%r)\n'
        'elif sys.argv[1] == "depends":\n'
        '    print(%r, end="")\n'
        'elif sys.argv[1] == "install":\n'
        '    sys.exit(%d)\n'
    ) % (meta_a, meta_b, depends, install_return_code)
    path.write_text(body)
    path.chmod(0o755)
    return path


class StubBackedOrchestratorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.dir = self.tmp / "firstrun.d"
        self.dir.mkdir()
        self.home = self.tmp / "home"
        self.home.mkdir()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run_main(self, args, stdin_text):
        """Run orchestrator.main() with a temp HOME and canned stdin; capture output."""
        import contextlib

        out, err = io.StringIO(), io.StringIO()
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.home)
        old_stdin = sys.stdin
        sys.stdin = io.StringIO(stdin_text)
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = orch.main([f"--firstrun-dir={self.dir}"])
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home
            sys.stdin = old_stdin
        return rc, out.getvalue(), err.getvalue()

    def _seed_installers(self, mapping):
        """mapping: filename -> (meta_id, meta_name, depends)."""
        for fname, (mid, mname, dep) in mapping.items():
            _make_stub(str(self.dir), fname, (mid, mname), dep)

    def test_empty_directory_touches_marker(self):
        rc, out, err = self._run_main([], "")
        self.assertEqual(rc, 0)
        self.assertIn("No first-run installer scripts found", out)
        self.assertTrue((self.home / ".devbox-install").exists())

    def test_meta_invalid_aborts(self):
        # name empty -> Invalid installer metadata
        self._seed_installers({"10-x.py": ("x", "", "")})
        rc, out, err = self._run_main("", "all\n")
        self.assertEqual(rc, 1)
        self.assertIn("Invalid installer metadata", err)
        self.assertFalse((self.home / ".devbox-install").exists())

    def test_duplicate_id_aborts(self):
        self._seed_installers(
            {"10-a.py": ("dup", "A", ""), "15-b.py": ("dup", "B", "")}
        )
        rc, out, err = self._run_main("", "all\n")
        self.assertEqual(rc, 1)
        self.assertIn("Duplicate first-run tool id detected: dup", err)

    def test_display_header_and_list(self):
        self._seed_installers(
            {"10-homebrew.py": ("homebrew", "Homebrew", ""),
             "15-fnm.py": ("fnm", "Fast Node Manager", "homebrew")}
        )
        rc, out, err = self._run_main([], "skip\n")
        self.assertEqual(rc, 0)  # skip-all -> no marker, no installs
        self.assertIn("DevBox first-run tool setup", out)
        self.assertIn("  1) Homebrew [homebrew]", out)
        self.assertIn("  2) Fast Node Manager [fnm]", out)
        self.assertIn("Skipping all first-run tool installs.", out)

    def test_install_all_creates_marker(self):
        # stubs "succeed" (return 0); verify full flow + marker + no failures
        self._seed_installers(
            {"10-homebrew.py": ("homebrew", "Homebrew", ""),
             "15-fnm.py": ("fnm", "Fast Node Manager", "homebrew")}
        )
        rc, out, err = self._run_main("", "all\n")
        self.assertEqual(rc, 0)
        self.assertIn("Installing: Homebrew", out)
        self.assertIn("Installing: Fast Node Manager", out)
        self.assertTrue((self.home / ".devbox-install").exists())

    def test_install_failure_does_not_mark_and_error(self):
        # good installs cleanly; bad exits 1 -> partial failure, no marker.
        self._seed_installers({"15-good.py": ("good", "Good", "")})
        _make_stub(str(self.dir), "10-bad.py", ("bad", "Bad"), "", install_return_code=1)
        rc, out, err = self._run_main("", "all\n")
        self.assertEqual(rc, 1)
        self.assertIn("Install failed: Bad [bad]", err)
        self.assertIn("1 tool(s) failed; not marking first-run complete", err)
        self.assertFalse((self.home / ".devbox-install").exists())

    def test_dependency_forcing_via_main(self):
        # Select only fnm; homebrew is forced into the install set.
        self._seed_installers(
            {"10-homebrew.py": ("homebrew", "Homebrew", ""),
             "15-fnm.py": ("fnm", "Fast Node Manager", "homebrew")}
        )
        rc, out, err = self._run_main("", "fnm\n")
        self.assertEqual(rc, 0)
        # homebrew installed before fnm even though only fnm was selected
        self.assertIn("Installing: Homebrew\nInstalling: Fast Node Manager", out)


class ShimGuardContractTests(unittest.TestCase):
    """The login hook stays a thin, non-exec bash guard.

    profile.d scripts are sourced into every interactive login shell, so the
    guard must NOT ``exec`` the orchestrator: doing so would replace the login
    shell and stop it from continuing to source the rest of profile.d (e.g.
    99-profile.sh PATH setup). It must instead launch ``python3`` in the
    foreground as a child process. ``shellcheck`` covers syntax; these checks
    cover the behavioral contract.
    """

    def test_shim_is_bash(self):
        self.assertTrue(SHIM_PATH.is_file())
        with SHIM_PATH.open() as fh:
            self.assertTrue(fh.read().startswith("#!/usr/bin/env bash"))

    def test_shim_invokes_orchestrator_in_foreground(self):
        with SHIM_PATH.open() as fh:
            code = "".join(
                ln for ln in fh
                if ln.strip() and not ln.lstrip().startswith("#")
            )
        self.assertIn("python3 /usr/local/bin/devbox-install", code)
        self.assertEqual(
            code.strip().splitlines()[-1], "python3 /usr/local/bin/devbox-install"
        )

    def test_shim_never_uses_exec(self):
        with SHIM_PATH.open() as fh:
            for ln in fh:
                stripped = ln.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                # A bare ``exec`` command would replace the login shell.
                self.assertNotRegex(stripped, r"^exec\b")


if __name__ == "__main__":
    unittest.main(verbosity=2)
