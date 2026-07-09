# Correctness harness (`cp_harness`)

Tests the **robustness and correctness** of `py2lean` by translating real Python solutions
to Lean, compiling them, and checking them against each problem's test cases — comparing the
Lean result to the expected output (and to the original Python).

It is **source-agnostic**: any HuggingFace (or other) dataset can be plugged in as a *source
adapter*. There is **no default source** — you always pick one with `--source`.

## Two test models

Every problem is fetched under one of two **test models**, recorded in a `kind` file. The
convert/evaluate stages dispatch purely on that marker, so different sources coexist in one
dataset dir.

| model | solution shape | tests | how it's run |
|-------|----------------|-------|--------------|
| **`stdio`** | reads `stdin`, prints `stdout` (CodeContests) | `tests/test_<i>.in` / `.out` | wrap in `__main__` → `lake env lean --run`, feed stdin, compare stdout |
| **`function`** | a callable (LeetCode `Solution.method`) | `tests/tests.json` = `[{input, output}]` | transpile the bare function → call `fn'rn args` in a generated `main`, compare the return value |

## Pipeline

```
fetch.py    --source <name>   download a dataset → normalized on-disk layout (+ a `kind` marker)
convert.py                    wrap (stdio) / bare (function) → py2lean → compile-check
evaluate.py                   stdio: stdin→stdout compare  |  function: call fn, compare return
```

### One command

```bash
bash cp_harness/run_all.sh --source codecontests 10       # 10 stdio problems, all tests
bash cp_harness/run_all.sh --source leetcode 20 8         # 20 function problems, 8 tests each
bash cp_harness/run_all.sh --source leetcode max          # the WHOLE dataset (no counting)
bash cp_harness/run_all.sh --skip-convert                 # just evaluate an existing dataset
```

`--num` (and the first positional to `run_all.sh`) accepts **`max`** / **`all`** to take every
problem; `--max-tests max` (or `0`) runs every test case.

### Or stage by stage

```bash
python3 cp_harness/fetch.py    --source leetcode --num 20 --out cp_harness/dataset
python3 cp_harness/convert.py  --dataset cp_harness/dataset
python3 cp_harness/evaluate.py --dataset cp_harness/dataset --max-tests 8
```

## Sources

Registered in `fetch.py` under `SOURCES` (see `python3 cp_harness/fetch.py --help` for the live list):

- **`codecontests`** — DeepMind `deepmind/code_contests`, Python3 solutions importing only `math`. Model: `stdio`.
- **`leetcode`** — `newfacade/LeetCodeDataset`; the entry method is extracted from `Solution` as a free function; `input_output` becomes the test cases. Model: `function`.

### Adding a new dataset

Write one **adapter** `fetch_<name>(args)` in `fetch.py` that pulls the dataset and writes the
normalized layout, tagging each problem with the right `kind`:

- **function-based** (HumanEval, MBPP, …): reuse `_function.py` — `extract_function`,
  `param_names`, and save `tests/tests.json` as `[{input, output}]` with `kind` = `function`.
- **stdio-based**: save `tests/test_<i>.in/.out` with `kind` = `stdio`.

Register it in `SOURCES`. **`convert.py` / `evaluate.py` need no changes** — they dispatch on `kind`.

## Dataset layout

```
dataset/<problem>/
  kind                         "stdio" | "function"   (which test model)
  problem.txt
  meta.json                    function model: { method, params, … }
  solutions/sol_<i>.py         stdio: original solution   |  function: entry method as a free `def`
  tests/test_<i>.in / .out     stdio test cases
  tests/tests.json             function test cases  [{input, output}, …]
  lean/sol_<i>.lean/.status/.log   generated Lean + ok|convert_fail|compile_fail + failure log
  eval/sol_<i>.json            per-solution pass/fail
dataset/convert_summary.json   conversion coverage across all problems
dataset/eval_report.json       python-vs-lean pass rates
dataset/eval_divergences.json  where compiling Lean disagreed with CPython (API-bug report)
```

## Fetch once, run repeatedly

Downloading is the slow network step; conversion/evaluation is the slow compute step you
re-run as py2lean improves. So fetch once, then re-run convert+evaluate+plot anytime:

```bash
# fetch ONCE (whole dataset; re-run only to change the corpus)
python3 cp_harness/fetch.py --source leetcode --num max --out cp_harness/dataset_leetcode

# convert + test + chart — repeat this every time (reuses the fetched problems)
bash cp_harness/run_all.sh --source leetcode --dataset cp_harness/dataset_leetcode --skip-fetch
```

## Coverage chart (LeetCode)

`plot.py` reads the converted+evaluated dataset and draws one grouped bar chart, **by
difficulty** (Easy / Medium / Hard), with three bars per difficulty:

- **didn't compile** — `convert_fail` / `compile_fail`
- **compiled · not all passed** — Lean elaborated but some/no test cases passed
- **compiled · all passed** — Lean elaborated and every test case passed

```bash
python3 cp_harness/plot.py --dataset cp_harness/dataset_leetcode
#  → cp_harness/dataset_leetcode/coverage_by_difficulty.png   (+ a text table)
```

`run_all.sh` runs this automatically as its last step for function-model datasets.

## Reading the results

- `convert_summary.json` — how much of the corpus py2lean can translate + compile, with a
  frequency histogram of failure reasons (unsupported constructs to prioritize).
- `eval_report.json` — for solutions that compiled, whether the Lean translation *preserves
  correctness*; the Lean pass rate should match the Python baseline.
- `eval_divergences.json` — the `lean_wrong_python_right` bucket pinpoints runtime/API bugs.

Note: `lake env lean --run` reloads Mathlib (~4–5s) per invocation, so this is a *correctness*
tool, not a speed benchmark — use `--max-tests` while iterating.

## Requirements

- `pip install datasets` (HuggingFace) for `fetch.py`.
- A built `py2lean` backend (`lake build py2lean`).
