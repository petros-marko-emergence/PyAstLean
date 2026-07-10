"""Everything that talks to Lean.

`client` drives the persistent `py2lean` server process (JSON IR in, Lean syntax out); `lean` shells
out to `lake` to elaborate and execute the Lean this produces. Nothing here knows about Python ASTs.
"""

from __future__ import annotations

from .client import (
    DEFAULT_PROVE_TIMEOUT,
    DEFAULT_REQUEST_TIMEOUT,
    DEFAULT_STARTUP_TIMEOUT,
    BackendError,
    LeanBackendClient,
)
from .lean import (
    CheckResult,
    Diagnostic,
    RunResult,
    compile_check,
    parse_diagnostics,
    run_program,
)

__all__ = [
    "BackendError",
    "CheckResult",
    "DEFAULT_PROVE_TIMEOUT",
    "DEFAULT_REQUEST_TIMEOUT",
    "DEFAULT_STARTUP_TIMEOUT",
    "Diagnostic",
    "LeanBackendClient",
    "RunResult",
    "compile_check",
    "parse_diagnostics",
    "run_program",
]
