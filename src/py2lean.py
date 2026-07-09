#!/usr/bin/env python3
"""Back-compat shim for `python3 src/py2lean.py <file> --target command`.

The transpiler now lives in the `pastalean` package (`pastalean.transpile.driver`) and is driven by
the `pastalean` console script. This file keeps the old invocation and the old importable names
(`translate_to_json`, `translate_to_lean`) working for the harnesses that shell out to it.

New code should use the package instead:

    from pastalean import Session, translate_file
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow running this file directly out of a source checkout, without installing the package.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from pastalean.transpile.driver import (  # noqa: E402,F401  (re-exported for old importers)
    configure_logging,
    translate_to_json,
    translate_to_lean,
)
from pastalean.legacy_cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
