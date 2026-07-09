# Correctness harness (`cp_harness`)

Tests the **robustness and correctness** of PastaLean by translating real Python solutions to Lean,
compiling them, and checking them against each problem's test cases — comparing the Lean result to
the expected output (and to the original Python).

Everything lives in one class, **`CPastaEval`** (`cpasta_eval.py`): it fetches, converts, evaluates,
plots, and selects. It is **source-agnostic** — any dataset plugs in as a *source adapter* — and
there is **no default source**.

## Two test models

Every problem is fetched under one of two **test models**, recorded in a `kind` file. Convert and
evaluate dispatch purely on that marker, so different sources coexist in one dataset directory.

| model | solution shape | tests | how it's run |
|-------|----------------|-------|--------------|
| **`stdio`** | reads `stdin`, prints `stdout` (CodeContests) | `tests/test_<i>.in` / `.out` | wrap in `__main__` → `lake env lean --run`, feed stdin, compare stdout |
| **`function`** | a callable (LeetCode `Solution.method`) | `tests/tests.json` | transpile the bare function → call `fn'rn args`, compare the return value |

## Usage

```bash
# fetch ONCE (downloading is the slow network step); `max`/`all` takes the whole dataset
python3 cp_harness/cpasta_eval.py fetch --source leetcode --num max --dataset cp_harness/dataset_leetcode

# then re-run convert+evaluate+plot as often as you like
python3 cp_harness/cpasta_eval.py run --skip-fetch --dataset cp_harness/dataset_leetcode

# a random 29 of the fetched problems (the seed is printed, so you can replay it)
python3 cp_harness/cpasta_eval.py run --skip-fetch --random 29
python3 cp_harness/cpasta_eval.py run --skip-fetch --random 29 --seed 7   # ...the same 29 every time

# individual stages
python3 cp_harness/cpasta_eval.py convert  --dataset <dir> [--random N] [--problems a b]
python3 cp_harness/cpasta_eval.py evaluate --dataset <dir> --max-tests 8
python3 cp_harness/cpasta_eval.py plot     --dataset <dir> --out coverage.png
```

`run_all.sh` is a thin shim that forwards to `cpasta_eval.py run`.

### Selection

`--random N` / `--seed S` / `--problems a b c` are honoured by convert, evaluate **and** plot. The
seed is chosen once per run, so every stage sees the *same* subset — otherwise convert and evaluate
would disagree about which problems they were working on.

`--num max` (fetch) takes every problem; `--max-tests max` (evaluate) runs every test case.

## As a library

```python
from cpasta_eval import CPastaEval

with CPastaEval("cp_harness/dataset_leetcode", source="leetcode", random_n=29, seed=7) as ev:
    ev.convert()
    ev.evaluate()
    ev.plot()
```

The `with` block holds one warm Lean backend (`pastalean.Session`) open for the whole run, so
Mathlib is imported once instead of once per solution.

## Adding a source

Write a `_save_<name>_problem(self, item, excluded)` that writes the normalized layout and tags the
problem with its `kind`, plus a `fetch_<name>(self, num)` that streams the dataset into
`_fetch_loop`. Register it in `CPastaEval.SOURCES`. Convert, evaluate, and plot need no changes.

- **`codecontests`** — DeepMind `deepmind/code_contests`, Python3 solutions importing only `math`. Model: `stdio`.
- **`leetcode`** — `newfacade/LeetCodeDataset`; the entry method is extracted from `Solution` as a
  free function, preceded by the dataset's own `prompt` preamble (pruned to what the solution
  reaches, so `inf`/`Counter`/`List` resolve). Model: `function`.

## Dataset layout

```
dataset/<problem>/
  kind                         "stdio" | "function"
  problem.txt
  meta.json                    function model: { method, params, difficulty }
  solutions/sol_<i>.py         the solution PastaLean converts
  solutions/_prompt.py         function model: the dataset's untouched prompt (provenance)
  tests/test_<i>.in / .out     stdio test cases
  tests/tests.json             function test cases
  lean/sol_<i>.lean/.status/.log   generated Lean + ok|convert_fail|compile_fail + failure log
  eval/sol_<i>.json            per-solution pass/fail
dataset/convert_summary.json   conversion coverage + failure-reason histogram
dataset/eval_report.json       python-vs-lean pass rates
dataset/eval_divergences.json  where compiling Lean disagreed with CPython (API-bug report)
dataset/coverage_by_difficulty.png
```

## Reading the results

- `convert_summary.json` — how much of the corpus translates + compiles, with a frequency histogram
  of failure reasons (the unsupported constructs to prioritize).
- `eval_report.json` — for solutions that compiled, whether the translation *preserves correctness*;
  the Lean pass rate should match the Python baseline.
- `eval_divergences.json` — the `lean_wrong_python_right` bucket pinpoints runtime/API bugs.

Note: `lake env lean --run` reloads Mathlib (~4–5s) per invocation, so this is a *correctness* tool,
not a speed benchmark — use `--max-tests` while iterating.

## Requirements

- `pip install datasets` (HuggingFace) for `fetch`; `sortedcontainers` (some LeetCode prompts import it).
- A built backend: `lake build py2lean`.
