#!/usr/bin/env python3
"""DevBox first-run installer orchestrator.

Enumerates the ``firstrun.d`` installer payloads, prompts for a selection, runs
``install`` on the chosen tools in ``depends``-driven topological order, and (on
full success) touches the first-run marker.

Stdlib only; Python 3.9+.

The interactive login-shell guard lives in ``profile.d/50-install-devbox.sh``
(a ~3-line bash shim that execs this program), so this module assumes it is
invoked only for interactive logins. All user-facing strings are copied verbatim
from the original bash orchestrator so the UX is byte-identical.

CLI (consumed by the shim):
    devbox-install [--firstrun-dir PATH]

    With no arguments it runs the interactive first-run flow.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_FIRSTRUN_DIR = "/firstrun.d"
MARKER_NAME = ".devbox-install"

# ---- verbatim messages (copied from 50-install-devbox.sh) ------------------
_HEADER = "DevBox first-run tool setup"
_HELP = (
    "Press Enter to install all tools, type none to skip all installs, or "
    "specify numbers/ids separated by spaces or commas."
)
_PROMPT = "Install selection [all]: "
_INVALID = (
    "Invalid selection. Use numbers, tool ids, none/skip, or press Enter for all."
)
_SKIP_MSG = "Skipping all first-run tool installs."
_INSTALLING = "Installing: {name}"
_INSTALL_FAILED = "\u274C Install failed: {name} [{id}]"
_COMPLETE = "First-run setup complete. Marker created: {marker}"
_FAILURE = (
    "\u26a0\uFE0F  {n} tool(s) failed; not marking first-run complete. "
    "Re-login to retry."
)
_NO_INSTALLERS = "No first-run installer scripts found in {dir}; marking first-run as complete."
_META_INVALID = "Invalid installer metadata from {script}"
_DUPLICATE_ID = "Duplicate first-run tool id detected: {id}"
_ENUMERATE_FAILED = "Failed to enumerate {dir} installer scripts."
_SORT_FAILED = "Failed to sort {dir} installer scripts."

_DECIMAL_RE = re.compile(r"[0-9]+")


class InstallerError(RuntimeError):
    """Fatal error that aborts the whole first-run run (printed to stderr)."""


class MetadataError(RuntimeError):
    """Malformed installer metadata (printed to stderr; aborts the run)."""


class DependencyCycleError(RuntimeError):
    """The ``depends`` graph contains a cycle (printed to stderr; aborts the run)."""


# ---- enumeration / meta loading --------------------------------------------
def marker_path(home=None):
    """Return the first-run marker path ($HOME/.devbox-install)."""
    if home is None:
        home = os.environ.get("HOME") or str(Path.home())
    return Path(home) / MARKER_NAME


def iter_installers(directory=DEFAULT_FIRSTRUN_DIR):
    """Return installer scripts in presentation (filename) order.

    Presentation order drives the numbered menu only; installation order is
    derived from ``depends`` separately (see :func:`ordered_targets`).
    """
    path = Path(directory)
    if not path.exists() or not path.is_dir():
        raise InstallerError(_ENUMERATE_FAILED.format(dir=directory))
    entries = [child for child in path.glob("*.py") if child.is_file()]
    # Full-path sort equals basename sort (shared parent prefix), mirroring the
    # bash orchestrator's locale-independent ``sort``.
    return sorted(entries)


def load_meta(path):
    """Run ``<path> meta`` and return ``(id, name)``.

    Mirrors the bash orchestrator, which does not treat a non-zero ``meta``
    exit as fatal: validation happens by checking id/name are present.
    """
    proc = subprocess.run([str(path), "meta"], stdout=subprocess.PIPE)
    text = proc.stdout.decode("utf-8", errors="replace").rstrip("\n")
    lines = text.split("\n") if text else []
    if len(lines) < 2 or not lines[0] or not lines[1]:
        raise MetadataError(_META_INVALID.format(script=path))
    return lines[0], lines[1]


def load_depends(path):
    """Run ``<path> depends`` and return the space-separated dep ids (``[]`` if none)."""
    proc = subprocess.run([str(path), "depends"], stdout=subprocess.PIPE)
    return proc.stdout.decode("utf-8").split()


def build_graph(scripts):
    """Return ``(ids, names, id_to_index, deps)`` after validating each installer.

    ``deps`` only references ids that are themselves loaded installers, so a
    stray dependency id can never drive an out-of-band install.
    """
    ids, names, id_to_index = [], [], {}
    deps = {}
    for script in scripts:
        try:
            tool_id, tool_name = load_meta(script)
        except MetadataError as exc:
            print(str(exc), file=sys.stderr)
            raise InstallerError(str(exc)) from exc
        if tool_id in id_to_index:
            print(_DUPLICATE_ID.format(id=tool_id), file=sys.stderr)
            raise InstallerError(_DUPLICATE_ID.format(id=tool_id))
        dep_ids = [d for d in load_depends(script) if d in id_to_index]
        ids.append(tool_id)
        names.append(tool_name)
        id_to_index[tool_id] = len(ids) - 1
        deps[tool_id] = dep_ids
    return ids, names, id_to_index, deps


# ---- selection parsing -----------------------------------------------------
def parse_selection(selection, ids, id_to_index):
    """Parse one prompt line.

    Returns a ``(mode, selected)`` tuple where ``mode`` is one of
    ``"all"``, ``"skip"``, ``"ok"`` or ``"invalid"`` and ``selected`` is a set of
    indices (possibly empty). Invalid input is a distinct mode so the caller can
    re-prompt.
    """
    selection = selection.replace(",", " ")
    low = selection.lower()
    if selection == "" or low == "all":
        return "all", set(range(len(ids)))
    if low in ("none", "skip", "0"):
        return "skip", set()
    selected = set()
    for token in selection.split():
        if _DECIMAL_RE.fullmatch(token):
            idx = int(token) - 1
            if idx < 0 or idx >= len(ids):
                return "invalid", set()
            selected.add(idx)
        elif token in id_to_index:
            selected.add(id_to_index[token])
        else:
            return "invalid", set()
    if not selected:
        return "invalid", set()
    return "ok", selected


def select_indices(ids, id_to_index, input_lines, prompt_sink=None):
    """Prompt and parse selections until a valid one is entered.

    ``input_lines`` is an iterable of stdin lines (each without a trailing
    newline); ``prompt_sink(msg)`` writes the prompt (default: stderr, matching
    bash ``read -p``). Returns ``(selected_indices, skip_all)``. A stream that
    ends (EOF) is treated as an empty selection, i.e. install all.
    """
    if prompt_sink is None:
        prompt_sink = lambda msg: (sys.stderr.write(msg), sys.stderr.flush())
    iterator = iter(input_lines)
    while True:
        prompt_sink(_PROMPT)
        try:
            selection = next(iterator)
        except StopIteration:
            selection = ""  # EOF mirrors bash read-at-EOF (empty -> all)
        mode, selected = parse_selection(selection, ids, id_to_index)
        if mode in ("all", "ok"):
            return sorted(selected), False
        if mode == "skip":
            return [], True
        # "invalid" -> re-prompt


# ---- dependency ordering ---------------------------------------------------
def transitive_closure(selected_ids, deps):
    """Return the transitive ``depends`` closure over ``selected_ids``.

    This is the *dependency-forcing* semantics: selecting a tool pulls in every
    transitive dependency regardless of what the user picked (e.g. selecting
    fnm forces homebrew).
    """
    closure = set()
    stack = list(selected_ids)
    while stack:
        node = stack.pop()
        if node in closure:
            continue
        closure.add(node)
        for dep in deps.get(node, ()):
            if dep not in closure:
                stack.append(dep)
    return closure


def ordered_targets(ids, deps, selected_indices):
    """Return the ids to install, in ``depends``-driven topological order.

    The install set is the dependency-forcing closure of the selected ids
    (:func:`transitive_closure`). Ties between nodes with no ``depends``
    relationship are broken in presentation (filename) order, so for the
    current installers the topological order coincides with the bash
    orchestrator's filename order.
    """
    rank = {tool_id: index for index, tool_id in enumerate(ids)}
    selected_ids = {ids[i] for i in selected_indices}
    closure = transitive_closure(selected_ids, deps)
    remaining = sorted(closure, key=lambda tool_id: rank[tool_id])
    placed = []
    placed_set = set()
    while remaining:
        progressed = False
        still = []
        for tool_id in remaining:
            unmet = [d for d in deps.get(tool_id, ()) if d in closure and d not in placed_set]
            if not unmet:
                placed.append(tool_id)
                placed_set.add(tool_id)
                progressed = True
            else:
                still.append(tool_id)
        remaining = still
        if not progressed:
            raise DependencyCycleError(
                "Cycle detected in first-run tool dependencies; refusing to install."
            )
    return placed


# ---- install / finalise ----------------------------------------------------
def run_installs(targets, id_to_script, names, ids):
    """Run ``install`` on each target in order; return the failure count."""
    id_to_name = {tool_id: name for tool_id, name in zip(ids, names)}
    failures = 0
    for tool_id in targets:
        print(_INSTALLING.format(name=id_to_name[tool_id]))
        try:
            proc = subprocess.run([str(id_to_script[tool_id]), "install"])
            ok = proc.returncode == 0
        except OSError:
            ok = False
        if not ok:
            print(_INSTALL_FAILED.format(name=id_to_name[tool_id], id=tool_id), file=sys.stderr)
            failures += 1
    return failures


def _touch_marker():
    marker_path().touch()


# ---- entry point -----------------------------------------------------------
def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)

    parser = argparse.ArgumentParser(
        prog="devbox-install",
        description="DevBox first-run tool setup.",
    )
    parser.add_argument(
        "--firstrun-dir",
        default=DEFAULT_FIRSTRUN_DIR,
        help="Directory of firstrun installers (default: %(default)s).",
    )
    parser.parse_args(argv)
    firstrun_dir = parser.parse_args(argv).firstrun_dir

    # Marker skip: first-run has already completed on a previous login.
    if marker_path().exists():
        return 0

    try:
        scripts = iter_installers(firstrun_dir)
    except InstallerError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if not scripts:
        print(_NO_INSTALLERS.format(dir=firstrun_dir))
        _touch_marker()
        return 0

    try:
        ids, names, id_to_index, deps = build_graph(scripts)
    except InstallerError:
        # Message already printed by build_graph.
        return 1

    print(_HEADER)
    for index, name in enumerate(names):
        print("  {0}) {1} [{2}]".format(index + 1, name, ids[index]))
    print(_HELP)

    selected_indices, skip_all = select_indices(
        ids,
        id_to_index,
        (line.rstrip("\n") for line in sys.stdin),
        prompt_sink=lambda msg: (sys.stderr.write(msg), sys.stderr.flush()),
    )

    if skip_all:
        print(_SKIP_MSG)
        return 0

    try:
        targets = ordered_targets(ids, deps, selected_indices)
    except DependencyCycleError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    id_to_script = {ids[index]: scripts[index] for index in range(len(ids))}
    failures = run_installs(targets, id_to_script, names, ids)

    if failures:
        print(_FAILURE.format(n=failures), file=sys.stderr)
        return 1

    _touch_marker()
    print(_COMPLETE.format(marker=marker_path()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
