"""LLM source-to-source passes that run *before* translation.

`--redesign` restructures a program to maximise its provable surface (per
`docs/verifiable-python-design.md`); `--contracts` annotates it with Requires/Ensures/Invariant
so the emitted Lean carries Hoare-triple obligations. Both rewrite the user's Python, so they are
a workflow around the transpiler rather than part of it.

The transformed source is written to a sibling `.py` file rather than piped straight through: the
annotation pre-pass re-reads the program by path, and it lets you inspect what the LLM produced.
"""

from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger("pastalean")


def add_llm_flags(parser) -> None:
    """Attach the pre-pass flags to a subcommand that takes a single Python file."""
    parser.add_argument(
        "-r", "--redesign", action="store_true",
        help="LLM pre-pass: restructure the Python to maximise its provable surface (pure "
             "single-expression math, IO/raise pushed to the edge) before translating. Runs "
             "before --contracts when both are given.",
    )
    parser.add_argument(
        "-c", "--contracts", action="store_true",
        help="LLM pre-pass: insert formal contracts (Requires/Ensures/Invariant/Assert) into the "
             "Python before translating.",
    )
    parser.add_argument(
        "--llm-provider", default="openai",
        help="Provider for --contracts/--redesign: openai, gemini, openrouter, deepinfra.",
    )
    parser.add_argument(
        "--llm-model", default=None,
        help="Model for --contracts/--redesign. Default: the provider's default chat model.",
    )
    parser.add_argument(
        "-u", "--user-prompt", dest="user_prompt", default=None,
        help="Natural-language goal for --contracts, e.g. -u \"prove the result equals n!\". "
             "Passed to the LLM so the inserted contracts target it.",
    )


def apply(file_path: str, args) -> str:
    """Run the requested pre-passes over `file_path`; return the path to translate.

    Returns `file_path` unchanged when neither `--redesign` nor `--contracts` was given.
    """
    if not (getattr(args, "redesign", False) or getattr(args, "contracts", False)):
        return file_path

    from .transpile import llm  # imported lazily: pulls in openai + dotenv

    source = Path(file_path).read_text(encoding="utf-8")
    applied = []
    if args.redesign:
        logger.info("LLM redesign pre-pass (provider=%s)...", args.llm_provider)
        source = llm.verifiable_design_code(source, provider=args.llm_provider, model=args.llm_model)
        applied.append("redesign")
    if args.contracts:
        logger.info("LLM contracts pre-pass (provider=%s)...", args.llm_provider)
        source = llm.contract_code(source, provider=args.llm_provider, model=args.llm_model,
                                   goal=getattr(args, "user_prompt", None))
        applied.append("contracts")

    original = Path(file_path)
    out_path = original.with_name(f"{original.stem}.{'.'.join(applied)}.py")
    out_path.write_text(source, encoding="utf-8")
    logger.warning("LLM %s pre-pass wrote transformed source to %s", "+".join(applied), out_path)
    return str(out_path)
