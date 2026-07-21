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

# src/paths.py -> src (the `pastalean` package) -> <repo root>
PACKAGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_DIR.parent

LIBRARIES_DIR = REPO_ROOT / "Libraries"
LAKE_BIN_DIR = REPO_ROOT / ".lake" / "build" / "bin"
BACKEND_BINARY = LAKE_BIN_DIR / "py2lean"


def lake_executable() -> str:
    """The `lake` binary, honouring PASTALEAN_LAKE then PATH."""
    return os.environ.get("PASTALEAN_LAKE") or shutil.which("lake") or "lake"
