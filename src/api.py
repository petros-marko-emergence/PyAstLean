"""The importable PastaLean API.

Translating a file boots a Lean backend that imports Mathlib — several seconds at best. A
`Session` holds that process open so a batch of files pays the cost once:

    from pastalean import Session

    with Session(mode="run") as s:
        for path in paths:
            result = s.translate_file(path)
            if result.ok:
                print(result.lean_code)

The module-level `translate` / `translate_file` helpers are the one-shot equivalents; they share a
process-wide backend that stays warm for the life of the interpreter.

Thread-safety: translation drives module-level state in `transpile.driver`, so a `Session`
serialises its own calls with a lock. Prefer one `Session` per thread for real parallelism.
"""

from __future__ import annotations

import json
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

from .backend import LeanBackendClient
from .paths import REPO_ROOT
# The module, not its names: `driver` carries mutable state (`_LAST_UNSUPPORTED`) that we read
# after each call, and a `from ... import` would freeze the binding at import time.
from .transpile import driver

TARGETS = ("command", "term")
MODES = ("prove", "run", "both")


class TranslationError(RuntimeError):
    """Translation failed and the caller asked for an exception rather than a result object."""


@dataclass
class TranslationResult:
    """Outcome of translating one Python source to Lean."""

    ok: bool
    lean_code: str | None = None
    error: str | None = None
    target: str = "command"
    mode: str = "both"
    source_path: Path | None = None
    #: Source lines that best-effort replaced with `pyUnsupported(...)` placeholders. Non-empty
    #: means the Lean compiles but does not faithfully implement the Python.
    unsupported: list[str] = field(default_factory=list)

    @property
    def degraded(self) -> bool:
        """True when the output contains `pyUnsupported` placeholders standing in for real logic."""
        return bool(self.unsupported) or (self.lean_code is not None and "pyUnsupported" in self.lean_code)

    def raise_for_status(self) -> "TranslationResult":
        if not self.ok:
            where = f" ({self.source_path})" if self.source_path else ""
            raise TranslationError(f"translation failed{where}: {self.error}")
        return self

    def __str__(self) -> str:
        return self.lean_code or ""


class Session:
    """A warm Lean backend plus the translation options to apply to every call."""

    def __init__(
        self,
        *,
        target: str = "command",
        mode: str = "both",
        best_effort: bool = True,
        prove_asserts: bool = True,
        imports_add: bool = True,
        repo_root: Path = REPO_ROOT,
        client: LeanBackendClient | None = None,
    ):
        if target not in TARGETS:
            raise ValueError(f"target must be one of {TARGETS}, got {target!r}")
        if mode not in MODES:
            raise ValueError(f"mode must be one of {MODES}, got {mode!r}")
        self.target = target
        self.mode = mode
        self.best_effort = best_effort
        self.prove_asserts = prove_asserts
        self.imports_add = imports_add
        self.client = client or LeanBackendClient(repo_root)
        self._lock = threading.Lock()

    def start(self) -> "Session":
        """Boot the backend now (imports Mathlib) rather than on the first translation."""
        self.client.start()
        return self

    def close(self) -> None:
        self.client.close()

    def __enter__(self) -> "Session":
        return self.start()

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _opts(self, overrides: dict[str, Any]) -> dict[str, Any]:
        opts = {
            "target": self.target,
            "mode": self.mode,
            "best_effort": self.best_effort,
            "prove_asserts": self.prove_asserts,
            "imports_add": self.imports_add,
        }
        unknown = set(overrides) - set(opts)
        if unknown:
            raise TypeError(f"unknown translation option(s): {sorted(unknown)}")
        opts.update(overrides)
        return opts

    def translate(self, source_code: str, *, filepath: str | Path | None = None, **overrides) -> TranslationResult:
        """Translate Python source text to Lean.

        Pass `filepath` when the source came from a file: the type-annotation pre-pass re-reads it
        by path, and without it inference is weaker.
        """
        opts = self._opts(overrides)
        path = Path(filepath) if filepath else None
        with self._lock:
            raw = driver.translate_to_lean(
                source_code,
                opts["target"],
                str(path) if path else None,
                imports_add=opts["imports_add"],
                best_effort=opts["best_effort"],
                mode=opts["mode"],
                prove_asserts=opts["prove_asserts"],
                client=self.client,
            )
            # Set by the front end during the call above; read under the same lock.
            unsupported = list(driver._LAST_UNSUPPORTED)

        if not isinstance(raw, dict) or raw.get("result") is False:
            error = raw.get("error", "translation failed") if isinstance(raw, dict) else str(raw)
            return TranslationResult(
                ok=False, error=error, target=opts["target"], mode=opts["mode"], source_path=path
            )

        code = raw.get(f"lean_{opts['target']}")
        if code is None:
            return TranslationResult(
                ok=False,
                error=f"backend returned no 'lean_{opts['target']}' field",
                target=opts["target"],
                mode=opts["mode"],
                source_path=path,
            )
        return TranslationResult(
            ok=True,
            lean_code=code,
            target=opts["target"],
            mode=opts["mode"],
            source_path=path,
            unsupported=unsupported,
        )

    def translate_file(self, path: str | Path, **overrides) -> TranslationResult:
        path = Path(path)
        return self.translate(path.read_text(encoding="utf-8"), filepath=path, **overrides)

    def translate_files(self, paths: Iterable[str | Path], **overrides) -> Iterator[TranslationResult]:
        """Translate many files through this one warm backend, yielding results as they finish."""
        for path in paths:
            try:
                yield self.translate_file(path, **overrides)
            except OSError as err:
                yield TranslationResult(ok=False, error=str(err), source_path=Path(path))

    def to_json_ir(self, source_code: str, *, filepath: str | Path | None = None, **overrides) -> dict:
        """The intermediate JSON IR, before the Lean backend sees it. Does not start the backend."""
        opts = self._opts(overrides)
        with self._lock:
            raw = driver.translate_to_json(
                source_code,
                str(filepath) if filepath else None,
                best_effort=opts["best_effort"],
            )
        return json.loads(raw)

    def to_json_ir_file(self, path: str | Path, **overrides) -> dict:
        path = Path(path)
        return self.to_json_ir(path.read_text(encoding="utf-8"), filepath=path, **overrides)


def _default_session(**kwargs) -> Session:
    """A Session bound to the process-wide backend, so one-shot helpers stay warm across calls."""
    return Session(client=driver._LEAN_BACKEND, **kwargs)


def translate(source_code: str, *, filepath: str | Path | None = None, **kwargs) -> TranslationResult:
    """One-shot translation of Python source text, reusing the process-wide warm backend."""
    session_opts = {k: kwargs.pop(k) for k in list(kwargs) if k in ("target", "mode", "best_effort", "prove_asserts", "imports_add")}
    return _default_session(**session_opts).translate(source_code, filepath=filepath, **kwargs)


def translate_file(path: str | Path, **kwargs) -> TranslationResult:
    """One-shot translation of a Python file, reusing the process-wide warm backend."""
    path = Path(path)
    return translate(path.read_text(encoding="utf-8"), filepath=path, **kwargs)


def supported_libraries() -> Sequence[str]:
    """Python libraries with a Lean shim under `Libraries/` (numpy, scipy, math, ...)."""
    return sorted(driver.SUPPORTED_LIBRARY_IMPORTS)
