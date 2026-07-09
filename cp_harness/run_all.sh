#!/usr/bin/env bash
# Thin shim: the harness lives in `CPastaEval` (cp_harness/cpasta_eval.py).
#
#   bash cp_harness/run_all.sh --source leetcode --num max
#   bash cp_harness/run_all.sh --skip-fetch --random 29
#   bash cp_harness/run_all.sh --skip-fetch --random 29 --seed 7   # ...the same 29, every time
#
# Every flag is forwarded to `cpasta_eval.py run` (see its --help).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec python3 cp_harness/cpasta_eval.py run "$@"
