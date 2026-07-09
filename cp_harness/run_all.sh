#!/usr/bin/env bash
# End-to-end correctness harness: fetch -> convert -> evaluate.
#
# Tests py2lean's robustness/correctness by translating real Python solutions to Lean,
# compiling them, and checking them against the problems' test cases. Works over any
# registered dataset SOURCE (there is no default): a "stdio" source like CodeContests
# (stdin/stdout, compared per test), or a "function" source like LeetCode (call the
# function, compare its return value). The convert/evaluate stages dispatch on the test
# MODEL each problem was fetched under, so both live in one dataset dir happily.
#
# Usage:
#   bash cp_harness/run_all.sh --source <name> [NUM] [MAX_TESTS] [flags]
#
# Sources (fetch adapters, see fetch.py SOURCES):  codecontests | leetcode | …
#
# Flags:
#   --source <name>   REQUIRED for fetching (no default). e.g. --source leetcode
#   --dataset <dir>   Dataset directory (default: cp_harness/dataset)
#   --skip-fetch      Reuse the existing dataset; do not (re-)download.
#   --skip-convert    Reuse already-converted Lean; only run evaluation. (Implies --skip-fetch.)
#   --skip-python     In evaluate, do not run the Python baseline.
#
# Examples:
#   bash cp_harness/run_all.sh --source codecontests 10        # 10 stdio problems, all tests
#   bash cp_harness/run_all.sh --source leetcode max            # ALL problems, all tests (no counting)
#   bash cp_harness/run_all.sh --source leetcode 20 8          # 20 problems, 8 tests each
#   bash cp_harness/run_all.sh --skip-convert                  # just evaluate the existing dataset
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE=""
DATASET="cp_harness/dataset"
SKIP_FETCH=0
SKIP_CONVERT=0
SKIP_PYTHON=0
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --source)    SOURCE="$2"; shift 2 ;;
    --source=*)  SOURCE="${1#*=}"; shift ;;
    --dataset)   DATASET="$2"; shift 2 ;;
    --dataset=*) DATASET="${1#*=}"; shift ;;
    --skip-fetch)   SKIP_FETCH=1; shift ;;
    --skip-convert) SKIP_CONVERT=1; SKIP_FETCH=1; shift ;;  # nothing to fetch if we reuse conversion
    --skip-python)  SKIP_PYTHON=1; shift ;;
    --*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

NUM="${POSITIONAL[0]:-10}"
MAX_TESTS="${POSITIONAL[1]:-0}"

echo "==================================================================="
echo " harness:  fetch $NUM problem(s)  ->  convert  ->  evaluate"
echo "==================================================================="

if [ "$SKIP_FETCH" = "0" ]; then
  if [ -z "$SOURCE" ]; then
    echo "ERROR: --source <name> is required to fetch (e.g. --source leetcode)." >&2
    echo "       Registered sources are listed by:  python3 cp_harness/fetch.py --help" >&2
    echo "       Or pass --skip-fetch / --skip-convert to reuse an existing dataset." >&2
    exit 2
  fi
  echo ""
  echo ">>> [1/3] Fetch (source: $SOURCE)"
  python3 cp_harness/fetch.py --source "$SOURCE" --num "$NUM" --out "$DATASET"
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
echo ">>> [4/4] Plot coverage by difficulty (function-model / LeetCode datasets)"
python3 cp_harness/plot.py --dataset "$DATASET" || echo "    (no function-model problems to plot — skipped)"

echo ""
echo "Done. See $DATASET/eval_report.json (pass rates),"
echo "      $DATASET/eval_divergences.json (Lean-vs-Python API divergences), and"
echo "      $DATASET/coverage_by_difficulty.png (the chart, for LeetCode datasets)."
