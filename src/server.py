"""HTTP API over a warm PastaLean backend.

    pastalean serve --port 8000

    curl -s localhost:8000/translate -H 'content-type: application/json' \
         -d '{"source": "def f(x):\n    return x + 1\n"}'

Requires the optional `server` extra:  uv pip install -e '.[server]'

One Lean backend serves every request, and translation drives process-wide state, so requests are
serialised behind a lock. This is a single-worker service by construction — run several processes
behind a load balancer if you need concurrency.
"""

# NOTE: no `from __future__ import annotations` here. The request models are defined inside
# `create_app` (so pydantic stays an optional import), and PEP 563 string annotations cannot be
# resolved from a function-local scope — FastAPI would silently treat the body model as a query
# parameter and reject every request with 422.

import logging
from contextlib import asynccontextmanager
from typing import Literal

from .api import Session, supported_libraries
from .backend import compile_check

logger = logging.getLogger(__name__)


def create_app(
    *,
    target: str = "command",
    mode: str = "both",
    best_effort: bool = True,
    prove_asserts: bool = True,
):
    try:
        from fastapi import FastAPI, HTTPException
        from pydantic import BaseModel, Field
    except ImportError as err:  # pragma: no cover
        raise RuntimeError(
            "the HTTP server needs the optional 'server' extra: uv pip install -e '.[server]'"
        ) from err

    session = Session(target=target, mode=mode, best_effort=best_effort, prove_asserts=prove_asserts)

    class TranslateRequest(BaseModel):
        source: str = Field(..., description="Python source text.")
        target: Literal["command", "term"] | None = None
        mode: Literal["prove", "run", "both"] | None = None
        best_effort: bool | None = None
        prove_asserts: bool | None = None

        def overrides(self) -> dict:
            return {
                key: value
                for key, value in (
                    ("target", self.target),
                    ("mode", self.mode),
                    ("best_effort", self.best_effort),
                    ("prove_asserts", self.prove_asserts),
                )
                if value is not None
            }

    class TranslateResponse(BaseModel):
        ok: bool
        lean: str | None = None
        error: str | None = None
        degraded: bool = False
        unsupported: list[str] = []

    class CheckResponse(TranslateResponse):
        compiles: bool = False
        diagnostics: list[str] = []

    @asynccontextmanager
    async def lifespan(_app):
        # Import Mathlib once at boot so the first real request is not the slow one.
        logger.info("booting Lean backend (importing Mathlib)...")
        session.start()
        logger.info("Lean backend ready")
        yield
        session.close()

    app = FastAPI(title="PastaLean", description="Python to Lean 4 transpiler.", lifespan=lifespan)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "target": session.target, "mode": session.mode}

    @app.get("/libraries")
    def libraries() -> dict:
        return {"libraries": list(supported_libraries())}

    @app.post("/translate", response_model=TranslateResponse)
    def translate(request: TranslateRequest) -> TranslateResponse:
        try:
            result = session.translate(request.source, **request.overrides())
        except SyntaxError as err:
            raise HTTPException(status_code=400, detail=f"invalid Python: {err}") from err
        except TypeError as err:
            raise HTTPException(status_code=400, detail=str(err)) from err
        return TranslateResponse(
            ok=result.ok,
            lean=result.lean_code,
            error=result.error,
            degraded=result.degraded,
            unsupported=result.unsupported,
        )

    @app.post("/check", response_model=CheckResponse)
    def check(request: TranslateRequest) -> CheckResponse:
        try:
            result = session.translate(request.source, **request.overrides())
        except SyntaxError as err:
            raise HTTPException(status_code=400, detail=f"invalid Python: {err}") from err
        if not result.ok:
            return CheckResponse(ok=False, error=result.error)
        report = compile_check(result.lean_code)
        return CheckResponse(
            ok=True,
            lean=result.lean_code,
            degraded=result.degraded,
            unsupported=result.unsupported,
            compiles=report.ok,
            diagnostics=[str(d) for d in report.diagnostics],
        )

    return app


def serve(
    *,
    host: str = "127.0.0.1",
    port: int = 8000,
    target: str = "command",
    mode: str = "both",
    best_effort: bool = True,
    prove_asserts: bool = True,
) -> None:
    try:
        import uvicorn
    except ImportError as err:  # pragma: no cover
        raise RuntimeError(
            "the HTTP server needs the optional 'server' extra: uv pip install -e '.[server]'"
        ) from err

    app = create_app(target=target, mode=mode, best_effort=best_effort, prove_asserts=prove_asserts)
    # Single worker: the Lean backend and the transpiler's module state are per-process.
    uvicorn.run(app, host=host, port=port, workers=1)
