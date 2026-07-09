"""The original `python3 src/py2lean.py` command line, kept verbatim for existing callers.

`cp_harness/`, `regen_examples.py`, the showcase runners and `PastaLeanTest/.../run_import_test.sh`
all shell out to this interface. New work should use `pastalean.cli` (the `pastalean` console
script) or the `pastalean.api` Session.

The LLM pre-passes (`--contracts` / `--redesign`) live here rather than in `pastalean.cli` because
they rewrite the user's source before translation, which is a workflow rather than a transpiler
concern.
"""
# ruff: noqa: N802  (`egProgram` keeps its original spelling for back-compat)

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .transpile.driver import configure_logging, translate_to_lean

logger = logging.getLogger(__name__)


def _run_llm_prepasses(file_path, source_code, args):
    """Apply the requested LLM pre-passes (`--redesign` then `--contracts`) to `source_code`, write the
    transformed program to a sibling `.py` file, and return its path for translation. The heavy lifting
    (prompts, provider/model handling) lives in `llm.py`; this only orchestrates and persists."""
    from .transpile import llm

    applied = []
    if args.redesign:
        logger.info("LLM redesign pre-pass (provider=%s)…", args.llm_provider)
        source_code = llm.verifiable_design_code(source_code, provider=args.llm_provider, model=args.llm_model)
        applied.append("redesign")
    if args.contracts:
        logger.info("LLM contracts pre-pass (provider=%s)…", args.llm_provider)
        source_code = llm.contract_code(source_code, provider=args.llm_provider, model=args.llm_model,
                                        goal=getattr(args, "user_prompt", None))
        applied.append("contracts")

    orig = Path(file_path)
    out_path = orig.with_name(f"{orig.stem}.{'.'.join(applied)}.py")
    out_path.write_text(source_code, encoding="utf-8")
    logger.warning("LLM %s pre-pass wrote transformed source to %s", "+".join(applied), out_path)
    return str(out_path)


def egProgram():
    return """def f(n):
    x = n + 1
    y = x * 2
    x = y - 1
    return x + y
"""


def main(argv=None):
    """CLI entry point that reads a file and forwards its contents to the translator."""
    parser = argparse.ArgumentParser(description="Translate a Python file to Lean.")
    parser.add_argument("file", nargs="?", help="Python source file to translate")
    parser.add_argument("--file", dest="file_option", help=argparse.SUPPRESS)
    parser.add_argument(
        "--target",
        nargs="?",
        default="command",
        help="Lean target string to pass to the translator (default: target)",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose output for debugging")
    parser.add_argument(
        "--strict",
        dest="strict",
        action="store_true",
        help="Disable the best-effort fallback (which is ON by default): fail hard on "
             "unsupported constructs (foreign libraries, unhandled syntax) instead of emitting "
             "pyUnsupported(...) placeholders.",
    )
    parser.add_argument(
        "--mode",
        dest="mode",
        choices=["prove", "run", "both"],
        default="both",
        help="Which numeric semantics to emit. 'prove': exact ℚ/ℝ (provable; transcendentals "
             "noncomputable). 'run': Float (fast, runnable). 'both' (default): emit BOTH in one file "
             "— the provable version under its name and a runnable twin suffixed 'rn "
             "(e.g. `main'rn`, `sigmoid'rn`).",
    )
    parser.add_argument(
        "-p",
        "--prove-asserts",
        dest="prove_asserts",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Run the prove-and-replace pass on each assert: elaborate in the warm backend and "
             "splice the concrete winning tactic — or `sorry` — over each `:= by taste?`. Default: "
             "on. Use --no-prove-asserts to leave the obligations as `:= by taste?`.",
    )
    parser.add_argument(
        "-r",
        "--redesign",
        action="store_true",
        help="LLM pre-pass: restructure the Python to maximise its provable surface (pure "
             "single-expression math, IO/raise pushed to the edge) per docs/verifiable-python-design.md "
             "BEFORE translating. Runs before --contracts when both are given.",
    )
    parser.add_argument(
        "-c",
        "--contracts",
        action="store_true",
        help="LLM pre-pass: insert formal contracts (Requires/Ensures/Invariant/Assert/…) into the "
             "Python BEFORE translating, so the emitted Lean carries provable Hoare-triple obligations.",
    )
    parser.add_argument(
        "--llm-provider",
        default="openai",
        help="LLM provider for --contracts/--redesign (openai, gemini, openrouter, deepinfra). "
             "Default: openai.",
    )
    parser.add_argument(
        "--llm-model",
        default=None,
        help="LLM model for --contracts/--redesign. Default: the provider's default chat model.",
    )
    parser.add_argument(
        "-u",
        "--user-prompt",
        dest="user_prompt",
        default=None,
        help="Optional natural-language goal for --contracts: what you want to be able to prove "
             "(e.g. -p \"I want to prove the result equals n!\"). Passed to the LLM so the inserted "
             "contracts/asserts are tailored to it.",
    )
    args = parser.parse_args(argv)
    configure_logging(args.verbose)

    file_path = args.file_option or args.file
    if not file_path:
        parser.error("the following arguments are required: file")

    source_code = Path(file_path).read_text(encoding="utf-8")

    # LLM pre-passes (optional). `--redesign` runs first (restructure for provability), then
    # `--contracts` (annotate the restructured code). Each rewrites the source; because the downstream
    # annotator re-reads the file by path, the transformed source is written to a sibling `.py` file and
    # translated from there — which also lets the user inspect exactly what the LLM produced.
    if args.redesign or args.contracts:
        file_path = _run_llm_prepasses(file_path, source_code, args)
        source_code = Path(file_path).read_text(encoding="utf-8")

    result = translate_to_lean(source_code, args.target, file_path, best_effort=not args.strict,
                               mode=args.mode, prove_asserts=args.prove_asserts)

    if isinstance(result, dict):
        if result.get("result") is False:
            print(result.get("error", "Translation failed."), file=sys.stderr)
            return 1

        code_key = f"lean_{args.target}"
        if code_key in result:
            logger.info("Successfully translated to Lean target '%s'.", args.target)
            print(result[code_key])
            return 0
    print("Unexpected translation result format.", file=sys.stderr)
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
