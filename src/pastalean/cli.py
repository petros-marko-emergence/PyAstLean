"""`pastalean` command-line interface.

    pastalean translate prog.py -o prog.lean
    pastalean check prog.py
    pastalean run prog.py < input.txt
    pastalean json prog.py
    pastalean batch example_scripts/commands -o out/
    pastalean serve --port 8000
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from .api import Session, TranslationResult
from .backend import lean as lean_tools

logger = logging.getLogger("pastalean")


def configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.WARNING,
        format="%(levelname)s: %(message)s",
    )


def _add_translation_flags(parser: argparse.ArgumentParser) -> None:
    """Flags shared by every subcommand that translates."""
    parser.add_argument(
        "--target",
        default="command",
        choices=["command", "term"],
        help="'command' emits top-level declarations for a whole program (default); "
             "'term' emits a single expression.",
    )
    parser.add_argument(
        "--mode",
        default="both",
        choices=["prove", "run", "both"],
        help="Numeric semantics. 'prove': exact Q/R (provable; transcendentals noncomputable). "
             "'run': Float (fast, runnable). 'both' (default): emit the provable version plus a "
             "runnable twin suffixed 'rn (e.g. main'rn).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Disable the best-effort fallback (ON by default): fail hard on unsupported "
             "constructs instead of emitting pyUnsupported(...) placeholders.",
    )
    parser.add_argument(
        "--prove-asserts",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Search for a proof of each assert and splice the winning tactic over ':= by taste?'. "
             "Default: on.",
    )


def _session_from(args, **overrides) -> Session:
    return Session(
        target=getattr(args, "target", "command"),
        mode=getattr(args, "mode", "both"),
        best_effort=not getattr(args, "strict", False),
        prove_asserts=getattr(args, "prove_asserts", True),
        **overrides,
    )


def _warn_if_degraded(result: TranslationResult) -> None:
    if result.ok and result.unsupported:
        logger.warning(
            "%d statement(s) degraded to pyUnsupported placeholders; the Lean compiles but does "
            "not faithfully implement the Python. Re-run with --strict to see the failures.",
            len(result.unsupported),
        )


def _emit(code: str, output: str | None) -> None:
    if output and output != "-":
        Path(output).write_text(code + "\n", encoding="utf-8")
    else:
        print(code)


def _fail(result: TranslationResult) -> int:
    print(f"error: {result.error}", file=sys.stderr)
    return 1


# --------------------------------------------------------------------------------------------
# subcommands


def cmd_translate(args) -> int:
    with _session_from(args) as session:
        result = session.translate_file(args.file)
    if not result.ok:
        return _fail(result)
    _warn_if_degraded(result)
    _emit(result.lean_code, args.output)
    return 0


def cmd_json(args) -> int:
    # The IR never reaches the Lean backend, so this needs no warm process.
    session = _session_from(args)
    ir = session.to_json_ir_file(args.file)
    _emit(json.dumps(ir, indent=2 if args.indent else None), args.output)
    return 0


def cmd_check(args) -> int:
    with _session_from(args) as session:
        result = session.translate_file(args.file)
    if not result.ok:
        return _fail(result)
    _warn_if_degraded(result)
    if args.output:
        Path(args.output).write_text(result.lean_code + "\n", encoding="utf-8")

    check = lean_tools.compile_check(result.lean_code, timeout=args.timeout)
    if check.ok:
        print(f"ok: {args.file} compiles")
        return 0
    print(f"compile failed: {args.file}", file=sys.stderr)
    for diagnostic in check.errors or []:
        print(f"  {diagnostic}", file=sys.stderr)
    if not check.errors:
        print(check.stderr or check.stdout, file=sys.stderr)
    return 1


def cmd_run(args) -> int:
    # A runnable program needs Float semantics; 'prove' emits noncomputable declarations.
    mode = args.mode if args.mode != "prove" else "run"
    with _session_from(args) as session:
        result = session.translate_file(args.file, mode=mode)
    if not result.ok:
        return _fail(result)
    _warn_if_degraded(result)
    if args.output:
        Path(args.output).write_text(result.lean_code + "\n", encoding="utf-8")

    stdin_text = "" if sys.stdin.isatty() else sys.stdin.read()
    run = lean_tools.run_program(result.lean_code, stdin=stdin_text, timeout=args.timeout)
    if run.stdout:
        sys.stdout.write(run.stdout)
    if run.stderr:
        sys.stderr.write(run.stderr)
    return 0 if run.ok else (run.returncode or 1)


def _batch_inputs(paths: list[str], recursive: bool) -> list[Path]:
    found: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            found.extend(sorted(path.rglob("*.py") if recursive else path.glob("*.py")))
        else:
            found.append(path)
    return found


def cmd_batch(args) -> int:
    files = _batch_inputs(args.paths, args.recursive)
    if not files:
        print("no .py files found", file=sys.stderr)
        return 1

    out_dir = Path(args.output) if args.output else None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    tally = {"ok": 0, "degraded": 0, "convert_fail": 0, "compile_fail": 0}
    records = []

    # One warm backend for the whole batch — this is the point of `batch`.
    with _session_from(args) as session:
        for path, result in zip(files, session.translate_files(files)):
            record = {"file": str(path)}
            if not result.ok:
                tally["convert_fail"] += 1
                record["status"] = "convert_fail"
                record["error"] = result.error
            else:
                if out_dir:
                    (out_dir / f"{path.stem}.lean").write_text(result.lean_code + "\n", encoding="utf-8")
                status = "degraded" if result.unsupported else "ok"
                if args.check:
                    check = lean_tools.compile_check(result.lean_code, timeout=args.timeout)
                    if not check.ok:
                        status = "compile_fail"
                        record["error"] = check.first_error()
                tally[status] += 1
                record["status"] = status
                if result.unsupported:
                    record["unsupported"] = result.unsupported
            records.append(record)
            if not args.quiet:
                print(f"{record['status']:>13}  {path}", flush=True)

    summary = {"total": len(files), **tally, "files": records}
    if args.summary:
        Path(args.summary).write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(
        f"\n{len(files)} file(s): {tally['ok']} ok, {tally['degraded']} degraded, "
        f"{tally['convert_fail']} convert_fail, {tally['compile_fail']} compile_fail",
        file=sys.stderr,
    )
    return 0 if (tally["convert_fail"] == 0 and tally["compile_fail"] == 0) else 1


def cmd_serve(args) -> int:
    from .server import serve  # imported lazily: fastapi/uvicorn are an optional extra

    serve(host=args.host, port=args.port, mode=args.mode, target=args.target,
          best_effort=not args.strict, prove_asserts=args.prove_asserts)
    return 0


def cmd_libraries(args) -> int:
    from .api import supported_libraries

    for name in supported_libraries():
        print(name)
    return 0


# --------------------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    from . import __version__

    parser = argparse.ArgumentParser(
        prog="pastalean",
        description="Transpile Python to Lean 4.",
    )
    parser.add_argument("--version", action="version", version=f"pastalean {__version__}")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose debug logging.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_translate = sub.add_parser("translate", help="Translate a Python file to Lean.")
    p_translate.add_argument("file", help="Python source file.")
    p_translate.add_argument("-o", "--output", help="Write Lean here instead of stdout ('-' for stdout).")
    _add_translation_flags(p_translate)
    p_translate.set_defaults(func=cmd_translate)

    p_check = sub.add_parser("check", help="Translate, then compile the Lean with `lake env lean`.")
    p_check.add_argument("file", help="Python source file.")
    p_check.add_argument("-o", "--output", help="Also write the generated Lean here.")
    p_check.add_argument("--timeout", type=float, default=600.0, help="Compile timeout in seconds.")
    _add_translation_flags(p_check)
    p_check.set_defaults(func=cmd_check)

    p_run = sub.add_parser("run", help="Translate, compile, and execute the program's main.")
    p_run.add_argument("file", help="Python source file.")
    p_run.add_argument("-o", "--output", help="Also write the generated Lean here.")
    p_run.add_argument("--timeout", type=float, default=600.0, help="Execution timeout in seconds.")
    _add_translation_flags(p_run)
    p_run.set_defaults(func=cmd_run)

    p_json = sub.add_parser("json", help="Dump the intermediate JSON IR.")
    p_json.add_argument("file", help="Python source file.")
    p_json.add_argument("-o", "--output", help="Write JSON here instead of stdout.")
    p_json.add_argument("--indent", action=argparse.BooleanOptionalAction, default=True,
                        help="Pretty-print the JSON. Default: on.")
    _add_translation_flags(p_json)
    p_json.set_defaults(func=cmd_json)

    p_batch = sub.add_parser("batch", help="Translate many files through one warm backend.")
    p_batch.add_argument("paths", nargs="+", help="Python files and/or directories.")
    p_batch.add_argument("-o", "--output", help="Directory to write .lean files into.")
    p_batch.add_argument("-r", "--recursive", action="store_true", help="Recurse into directories.")
    p_batch.add_argument("--check", action="store_true", help="Also compile each generated file.")
    p_batch.add_argument("--summary", help="Write a JSON summary here.")
    p_batch.add_argument("--quiet", action="store_true", help="Suppress the per-file lines.")
    p_batch.add_argument("--timeout", type=float, default=600.0, help="Per-file compile timeout.")
    _add_translation_flags(p_batch)
    p_batch.set_defaults(func=cmd_batch)

    p_serve = sub.add_parser("serve", help="Run the HTTP translation API.")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8000)
    _add_translation_flags(p_serve)
    p_serve.set_defaults(func=cmd_serve)

    p_libs = sub.add_parser("libraries", help="List Python libraries with a Lean shim.")
    p_libs.set_defaults(func=cmd_libraries)

    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    configure_logging(args.verbose)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 130
    except FileNotFoundError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
