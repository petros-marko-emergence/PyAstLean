"""`python -m pastalean ...` — the same entry point as the `pastalean` console script."""

from __future__ import annotations

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
