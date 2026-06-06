#!/usr/bin/env bash
# End-to-end CP correctness harness: fetch -> convert -> evaluate.
#
# Tests py2lean's robustness/correctness by translating real CodeContests Python solutions
# (math-only imports) to Lean, compiling them, and running them against the problems' long
# test cases — comparing Lean output to the expected output (and to the original Python).
#
# Usage:
#   bash cp_harness/run_all.sh [NUM_PROBLEMS] [MAX_TESTS_PER_SOL] [flags]
#
# Flags:
#   --skip-fetch      Reuse the existing dataset; do not (re-)download problems.
#   --skip-convert    Reuse the already-converted Lean; only run the evaluation step.
#                     (Implies --skip-fetch. Use this to "just check the tests" on a
#                      pre-converted dataset.)
#   --skip-python     In evaluate, do not run the Python baseline (no Lean-vs-Python diffs).
#
# Examples:
#   bash cp_harness/run_all.sh 10              # 10 problems, all tests, full pipeline
#   bash cp_harness/run_all.sh 5 5             # 5 problems, 5 tests each (fast iteration)
#   bash cp_harness/run_all.sh --skip-convert  # only evaluate the existing converted dataset
#   bash cp_harness/run_all.sh 5 0 --skip-convert
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DATASET="cp_harness/dataset"
SKIP_FETCH=0
SKIP_CONVERT=0
SKIP_PYTHON=0
POSITIONAL=()

for arg in "$@"; do
  case "$arg" in
    --skip-fetch)   SKIP_FETCH=1 ;;
    --skip-convert) SKIP_CONVERT=1; SKIP_FETCH=1 ;;  # nothing to fetch if we reuse the conversion
    --skip-python)  SKIP_PYTHON=1 ;;
    --*) echo "Unknown flag: $arg" >&2; exit 2 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

NUM="${POSITIONAL[0]:-10}"
MAX_TESTS="${POSITIONAL[1]:-0}"

echo "==================================================================="
echo " CP harness:  fetch $NUM problem(s)  ->  convert  ->  evaluate"
echo "==================================================================="

if [ "$SKIP_FETCH" = "0" ]; then
  echo ""
  echo ">>> [1/3] Fetch"
  python3 cp_harness/fetch.py --num "$NUM" --out "$DATASET"
else
  echo ""
  echo ">>> [1/3] Fetch (skipped — reusing existing dataset)"
fi

if [ "$SKIP_CONVERT" = "0" ]; then
  echo ""
  echo ">>> [2/3] Convert (Python -> Lean -> compile-check)"
  python3 cp_harness/convert.py --dataset "$DATASET"
else
  echo ""
  echo ">>> [2/3] Convert (skipped — reusing already-converted Lean)"
fi

echo ""
echo ">>> [3/3] Evaluate (run Lean vs Python on test cases)"
EVAL_ARGS=(--dataset "$DATASET")
if [ "$MAX_TESTS" != "0" ]; then
  EVAL_ARGS+=(--max-tests "$MAX_TESTS")
fi
if [ "$SKIP_PYTHON" = "1" ]; then
  EVAL_ARGS+=(--skip-python)
fi
python3 cp_harness/evaluate.py "${EVAL_ARGS[@]}"

echo ""
echo "Done. See $DATASET/eval_report.json (pass rates) and"
echo "      $DATASET/eval_divergences.json (Lean-vs-Python API divergences)."
