"""Python source → JSON IR, and the driver that feeds it to the Lean backend.

Pipeline order (see `driver.translate_to_json`):

    annotate_python   type/scope annotations, run as a subprocess over the original file
    node_visitor      Python AST → JSON IR
    normalize_loops   canonical counting `while` → `for i in range(...)`
    driver            library-import, effect, real-flow and top-level-state annotations
    toplevel_state    entry-point + state-threading annotations

`contract_passta` describes the PASSTA contract shim's surface; `llm` holds the optional
source-rewriting pre-passes (`--contracts` / `--redesign`).

Mutable module state (`_LAST_UNSUPPORTED`, `_NUMERIC_MODE`) lives on `driver`. Import the module
(`from .transpile import driver`) rather than the names, or you will read a stale binding.
"""

from __future__ import annotations

from .driver import (
    LIBRARY_IMPORT_ALIASES,
    LIBRARY_SUBMODULES,
    SUPPORTED_LIBRARY_IMPORTS,
    TYPE_ONLY_IMPORTS,
    configure_logging,
    get_supported_libraries,
    translate_to_json,
    translate_to_lean,
)

__all__ = [
    "LIBRARY_IMPORT_ALIASES",
    "LIBRARY_SUBMODULES",
    "SUPPORTED_LIBRARY_IMPORTS",
    "TYPE_ONLY_IMPORTS",
    "configure_logging",
    "driver",
    "get_supported_libraries",
    "translate_to_json",
    "translate_to_lean",
]
