"""HTTP API over a warm PastaLean backend. Two POST routes, mirroring the CLI:

    POST /translate   Python -> Lean, and compile-check it   (`pastalean translate`)
    POST /run         ... and execute the program's `main`    (`pastalean run`)

    pastalean serve --port 8000

    curl -s localhost:8000/translate -H 'content-type: application/json' \
         -d '{"source": "def f(x):\n    return x + 1\n"}'

Interactive docs at `/docs`, schema at `/openapi.json`. Requires the optional `server` extra:
`uv pip install -e '.[server]'`.

One Lean backend serves every request, and translation drives process-wide state, so requests are
serialised behind a lock. This is a single-worker service by construction — run several processes
behind a load balancer if you need concurrency.

There is no authentication, and `/run` executes the caller's program. Bind it to localhost unless
you trust everyone who can reach the port.
"""

# NOTE: no `from __future__ import annotations` here. The request models are defined inside
# `create_app` (so pydantic stays an optional import), and PEP 563 string annotations cannot be
# resolved from a function-local scope — FastAPI would silently treat the body model as a query
# parameter and reject every request with 422.

import ast
import logging
import time
from contextlib import asynccontextmanager
from typing import Literal

from .api import Session, supported_libraries
from .backend import compile_check, run_program
from .paths import PACKAGE_DIR
from .pyexec import run_python

logger = logging.getLogger(__name__)

STATIC_DIR = PACKAGE_DIR / "static"


def create_app(
    *,
    target: str = "command",
    mode: str = "both",
    best_effort: bool = True,
    prove_asserts: bool = True,
):
    try:
        from fastapi import FastAPI, HTTPException
        from fastapi.responses import FileResponse, HTMLResponse
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
        check: bool = Field(True, description="Compile the generated Lean with `lake env lean`.")
        timeout: float = Field(600.0, gt=0, description="Seconds allowed for the Lean step.")

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

    class RunRequest(TranslateRequest):
        stdin: str = Field("", description="Text fed to the program's standard input.")

    class LLMRequest(BaseModel):
        """`api_key` overrides the server's environment key, and is never logged or stored."""

        provider: Literal["openai", "gemini", "openrouter", "deepinfra"] = "gemini"
        api_key: str | None = None

    class ModelsResponse(BaseModel):
        models: list[str] = []

    class ContractsRequest(LLMRequest):
        source: str = Field(..., description="Python source to annotate with contracts.")
        model: str | None = Field(None, description="Defaults to the provider's default chat model.")
        goal: str | None = Field(None, description="What you want to prove; tailors the contracts.")

    class ContractsResponse(BaseModel):
        # `ok` is false when the model returned something that is not parsable Python — `source` still
        # carries it, so the caller can look at what went wrong instead of guessing.
        ok: bool
        source: str | None = None
        error: str | None = None
        model: str | None = None

    class Translation(BaseModel):
        """What both routes report about the translation itself. `ok` is about *translating*, not
        about whether the Lean compiled or the program succeeded — read `compiles` / `exit_code`."""

        ok: bool
        lean: str | None = None
        error: str | None = None
        degraded: bool = False
        unsupported: list[str] = []

    class TranslateResponse(Translation):
        # `None` when the request set check=false; otherwise whether `lake env lean` accepted it.
        compiles: bool | None = None
        diagnostics: list[str] = []
        translate_seconds: float | None = None
        compile_seconds: float | None = None

    class RunResponse(Translation):
        stdout: str = ""
        stderr: str = ""
        exit_code: int | None = None
        timed_out: bool = False

    @asynccontextmanager
    async def lifespan(_app):
        # Import Mathlib once at boot so the first real request is not the slow one.
        logger.info("booting Lean backend (importing Mathlib)...")
        session.start()
        logger.info("Lean backend ready")
        yield
        session.close()

    app = FastAPI(
        title="PastaLean",
        description="Python to Lean 4 transpiler.",
        lifespan=lifespan,
        docs_url="/api",   # `/` is the web UI; the generated reference lives at /api
        redoc_url=None,
    )

    @app.get("/", response_class=HTMLResponse, include_in_schema=False)
    def index() -> str:
        return (STATIC_DIR / "index.html").read_text(encoding="utf-8")

    @app.get("/logo.png", include_in_schema=False)
    def logo() -> FileResponse:
        return FileResponse(STATIC_DIR / "logo.png", media_type="image/png")

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "target": session.target, "mode": session.mode}

    @app.get("/libraries")
    def libraries() -> dict:
        return {"libraries": list(supported_libraries())}

    def _translate(request: TranslateRequest, **overrides):
        """Translate, mapping a bad program to HTTP 400 rather than a 500."""
        try:
            return session.translate(request.source, **{**request.overrides(), **overrides})
        except SyntaxError as err:
            raise HTTPException(status_code=400, detail=f"invalid Python: {err}") from err
        except TypeError as err:
            raise HTTPException(status_code=400, detail=str(err)) from err

    @app.post("/translate", response_model=TranslateResponse)
    def translate(request: TranslateRequest) -> TranslateResponse:
        # `perf_counter`, not `time()`: a monotonic clock cannot be dragged backwards by NTP.
        started = time.perf_counter()
        result = _translate(request)
        translate_seconds = time.perf_counter() - started
        if not result.ok:
            return TranslateResponse(ok=False, error=result.error, translate_seconds=translate_seconds)
        response = TranslateResponse(
            ok=True,
            lean=result.lean_code,
            degraded=result.degraded,
            unsupported=result.unsupported,
            translate_seconds=translate_seconds,
        )
        if request.check:
            started = time.perf_counter()
            report = compile_check(result.lean_code, timeout=request.timeout)
            response.compile_seconds = time.perf_counter() - started
            response.compiles = report.ok
            response.diagnostics = [str(d) for d in report.diagnostics]
        return response

    @app.post("/run", response_model=RunResponse)
    def run(request: RunRequest) -> RunResponse:
        # A runnable program needs Float semantics; 'prove' emits noncomputable declarations.
        mode = request.mode or session.mode
        result = _translate(request, mode="run" if mode == "prove" else mode)
        if not result.ok:
            return RunResponse(ok=False, error=result.error)

        # No separate compile step: `lake env lean --run` elaborates before it executes, so
        # checking first would pay for elaboration twice. Compile errors surface in `stderr`.
        report = run_program(result.lean_code, stdin=request.stdin, timeout=request.timeout)
        return RunResponse(
            ok=True,
            lean=result.lean_code,
            degraded=result.degraded,
            unsupported=result.unsupported,
            stdout=report.stdout,
            stderr=report.stderr,
            exit_code=report.returncode,
            timed_out=report.timed_out,
        )

    @app.post("/run/python", response_model=RunResponse)
    def run_the_python(request: RunRequest) -> RunResponse:
        """Execute the *original* Python, so its output can be diffed against the Lean twin's."""
        report = run_python(request.source, stdin=request.stdin, timeout=request.timeout)
        return RunResponse(
            ok=True,
            stdout=report.stdout,
            stderr=report.stderr,
            exit_code=report.returncode,
            timed_out=report.timed_out,
        )

    # -- LLM pre-passes -----------------------------------------------------------------------

    @app.get("/llm/providers")
    def llm_providers() -> dict:
        """The providers, their default models, and whether this server already has a key for each."""
        from .transpile import llm

        return {"providers": [
            {
                "id": name.lower(),
                "name": info["name"],
                "default_model": info["default_model"],
                "models_url": info["models_url"],
                "has_server_key": llm.env_api_key(name) is not None,
            }
            for name, info in llm.provider_info.items()
        ]}

    @app.post("/llm/models", response_model=ModelsResponse)
    def llm_models(request: LLMRequest) -> ModelsResponse:
        """Ask the provider which models this key may use."""
        from .transpile import llm

        try:
            return ModelsResponse(models=llm.get_supported_models(request.provider, request.api_key))
        except llm.LLMError as err:
            raise HTTPException(status_code=400, detail=str(err)) from err

    @app.post("/contracts", response_model=ContractsResponse)
    def contracts(request: ContractsRequest) -> ContractsResponse:
        """Insert Requires/Ensures/Invariant contracts into the Python — the `--contracts` pre-pass.

        Returns the annotated source; it is not translated. Feed it back to /translate to see the
        Hoare-triple obligations it produces.
        """
        from .transpile import llm

        model = request.model or llm.default_model_for(request.provider)
        try:
            annotated = llm.contract_code(request.source, provider=request.provider, model=model,
                                          goal=request.goal, api_key=request.api_key)
        except llm.LLMError as err:
            raise HTTPException(status_code=400, detail=str(err)) from err
        except Exception as err:  # noqa: BLE001  (provider transport errors are the caller's problem)
            return ContractsResponse(ok=False, error=str(err), model=model)

        # Models do drift into pseudo-code — `Ensures(Result() == <n!>)` rather than a real call.
        # Say so here, rather than letting the translator fail on it later.
        try:
            ast.parse(annotated)
        except SyntaxError as err:
            return ContractsResponse(ok=False, source=annotated, model=model,
                                     error=f"the model returned code that is not valid Python: {err}")
        return ContractsResponse(ok=True, source=annotated, model=model)

    return app


def lan_address() -> str | None:
    """This machine's address on the LAN (e.g. 10.x / 192.168.x), or None if it has no route out.

    Connecting a UDP socket sends no packets; it only asks the kernel which local interface it
    *would* use to reach that address. So this works offline and needs no name resolution.
    """
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("10.255.255.255", 1))
            return probe.getsockname()[0]
        except OSError:
            return None


def serve(
    *,
    host: str = "0.0.0.0",  # noqa: S104  (LAN-reachable by default; pass "127.0.0.1" to restrict)
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

    # flush=True: redirected stdout is block-buffered, so these would otherwise surface long after
    # uvicorn's own banner — or not at all until the server exits.
    every_interface = host == "0.0.0.0"  # noqa: S104
    local = f"http://{'127.0.0.1' if every_interface else host}:{port}"
    print(f"ui:   {local}", flush=True)
    print(f"api:  {local}/api", flush=True)
    if every_interface:
        if lan := lan_address():
            print(f"lan:  http://{lan}:{port}", flush=True)
        print("warning: reachable from the network, with no authentication, and POST /run executes "
              "the caller's program. Anyone who can reach this port can run code as you. "
              "Restrict it with --no-ip.", flush=True)

    # Single worker: the Lean backend and the transpiler's module state are per-process.
    uvicorn.run(app, host=host, port=port, workers=1)
