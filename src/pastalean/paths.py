"""Filesystem locations PastaLean needs at runtime.

Everything is resolved from `__file__`, so the package works from any working directory
and from an installed (non-editable) checkout. `REPO_ROOT` is the directory holding
`lakefile.toml` — the cwd `lake` must run in.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

# src/pastalean/paths.py -> src/pastalean -> src -> <repo root>
PACKAGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_DIR.parent.parent

# Kept as aliases: the pre-split `py2lean.py` used these names.
HOMEDIR = REPO_ROOT
SRC_DIR = PACKAGE_DIR

# The type-annotation pre-pass runs in its own interpreter, so it is referenced by path, not import.
ANNOTATE_SCRIPT = PACKAGE_DIR / "transpile" / "annotate_python.py"

LIBRARIES_DIR = REPO_ROOT / "Libraries"
LAKE_BIN_DIR = REPO_ROOT / ".lake" / "build" / "bin"
BACKEND_BINARY = LAKE_BIN_DIR / "py2lean"


def python_executable() -> str:
    """Interpreter used to run the `annotate_python.py` pre-pass in a subprocess.

    Prefers the repo's uv venv, then the running interpreter. `annotate_python.py` needs the
    project's dependencies (libcst, pyrefly), so a bare `python3` off PATH is the last resort.
    """
    override = os.environ.get("PASTALEAN_PYTHON")
    if override:
        return override
    venv_python = REPO_ROOT / ".venv" / "bin" / "python"
    if venv_python.exists():
        return str(venv_python)
    if sys.executable:
        return sys.executable
    return shutil.which("python3") or "python3"


def lake_executable() -> str:
    """The `lake` binary, honouring PASTALEAN_LAKE then PATH."""
    return os.environ.get("PASTALEAN_LAKE") or shutil.which("lake") or "lake"
