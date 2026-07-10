"""PastaLean — a Python to Lean 4 transpiler.

    >>> import pastalean
    >>> result = pastalean.translate_file("prog.py", mode="run")
    >>> if result.ok:
    ...     print(result.lean_code)

Use `Session` to translate many files through one warm Lean backend. See `pastalean.api`.
"""

from __future__ import annotations

from .api import (
    MODES,
    TARGETS,
    Session,
    TranslationError,
    TranslationResult,
    supported_libraries,
    translate,
    translate_file,
)
from .backend import (
    BackendError,
    CheckResult,
    Diagnostic,
    LeanBackendClient,
    RunResult,
    compile_check,
    run_program,
)
from .paths import REPO_ROOT

try:  # populated when the package is installed; falls back for a bare source checkout
    from importlib.metadata import PackageNotFoundError, version

    __version__ = version("pastalean")
except Exception:  # pragma: no cover
    __version__ = "0.1.0"

__all__ = [
    "BackendError",
    "CheckResult",
    "Diagnostic",
    "LeanBackendClient",
    "MODES",
    "REPO_ROOT",
    "RunResult",
    "Session",
    "TARGETS",
    "TranslationError",
    "TranslationResult",
    "__version__",
    "compile_check",
    "run_program",
    "supported_libraries",
    "translate",
    "translate_file",
]
