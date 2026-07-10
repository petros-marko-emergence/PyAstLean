# PastaLean

PastaLean is a tool that converts Python code into Lean 4.

PastaLean originates from "PyAstLean"(which mean Python to Lean via AST) but who doesn't love Pasta.

## Install

Build the Lean side from the repository root:

```bash
lake build
```

Then either let `uv` handle the Python side for you — it installs the project into `.venv/` on
first use, so there is no separate install step:

```bash
uv run pastalean translate prog.py
```

or install it yourself, which additionally puts `pastalean` on your PATH:

```bash
uv pip install -e '.[server]'      # drop [server] if you don't want the HTTP API
pastalean translate prog.py
```

`python -m pastalean` and `uv run -m pastalean` are equivalent to the `pastalean` command.
(`uv run src/main.py` does *not* work — the package uses relative imports, and running a file by
path gives it no package to be relative to.)

## Command line

```bash
pastalean translate prog.py              # Python -> Lean on stdout, then compile-check it
pastalean run       prog.py < input.txt  # translate, compile, execute
pastalean json      prog.py              # dump the intermediate JSON IR
pastalean batch     example_scripts/commands -o out/ --check   # many files, one warm backend
pastalean serve     --port 8000          # HTTP API
pastalean libraries                      # Python libs with a Lean shim
```

`translate` writes the Lean to stdout and *then* type-checks it with `lake env lean`, reporting
diagnostics on stderr. So `pastalean translate prog.py > prog.lean` still writes clean Lean, the
errors reach your terminal, and the exit status is non-zero if the Lean does not compile. Pass
`--no-check` to skip the compile and get codegen only, which is much faster.

Flags shared by `translate`, `run`, `json`, and `batch`:

| Flag | Meaning |
| --- | --- |
| `--target command\|term` | Top-level declarations (default) or a single expression. |
| `--mode prove\|run\|both` | Exact ℚ/ℝ (provable), `Float` (runnable), or both in one file (default). |
| `--strict` | Fail on unsupported constructs instead of emitting `pyUnsupported(...)` placeholders. |
| `--no-prove-asserts` | Leave each assert as `:= by taste?` rather than searching for a proof. |
| `-v` | Dump the intermediate JSON IR and Lean syntax. |

`translate` and `run` also accept the LLM source rewrites `-r/--redesign` (restructure for
provability) and `-c/--contracts` (insert Requires/Ensures/Invariant). Both write the transformed
program to a sibling `.py` so you can read what the model produced.

## HTTP API

```bash
pastalean serve --port 8000        # localhost only
pastalean serve --lan --port 8000  # every interface; prints this machine's LAN URL
```

Interactive documentation is generated from the code and served at **`/docs`**; the machine-readable
schema is at `/openapi.json`. Those are the authoritative reference — the table below is a summary.

The two POST routes mirror the two CLI verbs.

| Route | Body | Returns |
| --- | --- | --- |
| `GET /health` | — | `{"status", "target", "mode"}` |
| `GET /libraries` | — | `{"libraries": [...]}` |
| `POST /translate` | `{"source", ...}` | `{"ok", "lean", "error", "degraded", "unsupported", "compiles", "diagnostics"}` |
| `POST /run` | `{"source", "stdin", ...}` | `{"ok", "lean", ..., "stdout", "stderr", "exit_code", "timed_out"}` |

Both bodies take `source` plus optional per-request overrides of the server's defaults: `target`,
`mode`, `best_effort`, `prove_asserts`, `check`, `timeout`. `/run` also takes `stdin`.

`ok` reports whether the *translation* succeeded. Whether the Lean compiled is `compiles` (`null`
if you passed `check: false`), and whether the program succeeded is `exit_code`. `/run` does not
compile separately — `lake env lean --run` elaborates before executing, so compile errors arrive
in `stderr`.

```bash
curl -s localhost:8000/translate -H 'content-type: application/json' \
     -d '{"source": "def f(x: int) -> int:\n    return x + 1\n"}'

curl -s localhost:8000/run -H 'content-type: application/json' \
     -d '{"source": "def main():\n    print(int(input()) + 10)\n\nif __name__ == \"__main__\":\n    main()\n",
          "stdin": "32\n", "mode": "run"}'      # -> {"stdout": "42\n", "exit_code": 0, ...}
```

Invalid Python returns HTTP 400. One Lean backend serves every request and translation drives
process-wide state, so requests are serialised behind a lock — this is a single-worker service by
construction.

**`/run` executes the caller's program, and there is no authentication.** `--lan` therefore hands
code execution to everyone who can reach the port. Keep it on localhost unless you trust the network.

## Python API

```python
import pastalean

result = pastalean.translate_file("prog.py", mode="run")
if result.ok:
    print(result.lean_code)

# Many files, one Lean boot:
with pastalean.Session(target="command", mode="run") as session:
    for result in session.translate_files(paths):
        ...
```

Booting the backend imports Mathlib and takes tens of seconds, so a `Session` is much faster
than one process per file. `pastalean.compile_check` and `pastalean.run_program` take Lean text
and shell out to `lake env lean`.

## How a translation works

1. Read the Python file.
2. Run the annotation pre-pass (`src/transpile/annotate_python.py`).
3. Convert the Python AST to a JSON IR (`src/transpile/node_visitor.py`).
4. Send one JSON translation request per top-level statement to the Lean backend.
5. Reuse a single persistent Lean process for the lifetime of the Python process, so
   module-level translation does not restart Lean for every statement.

### Low-level Lean backend

The executable defined by [py2lean.lean](/home/anirudhgupta/PastaLean/py2lean.lean:1) is the JSON backend.

It expects:

1. A JSON task string as the first argument.
2. An optional target as the second argument, usually `term` or `command`.

Example:

```bash
lake exe py2lean '{"task":"translate","ast":{"node_type":"Constant","value":1}}' term
```

Typical stdout:

```json
{"result": true, "lean_term": "(1 : Int)"}
```

The backend also supports a persistent server mode for tooling and performance-sensitive
workflows:

```bash
lake env .lake/build/bin/py2lean --server
```

It accepts one compact JSON request per line on stdin and writes one compact JSON response
per line on stdout. The Python wrapper uses this mode automatically.

## Installation

To install PastaLean as a dependency, add the following to your `lakefile.toml`:

```toml
[[require]]
name = "PastaLean"
git = "https://github.com/Siddhartha-Gadgil/PastaLean.git"
rev = "v4.29.0"
```

### Dependencies

For Python-side annotation, the project uses `pyrefly` and `libcst`. Set up the Python environment with one of the following:

```bash
# If you use uv (recommended)
uv pip install -r requirements.txt
uv sync

# If you use pip
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Libraries

Python libraries can be supported in PastaLean by writing Lean definitions that correspond to the Python library's API. These definitions can be made by implementing the necessary translation logic in the Lean backend, then added to PastaLean by creating a mapping using `Mapping.lean` which is simply a map from python name for a function to Your Lean definition.

For example, see [math](./Libraries/math/) library, which uses Mathlib to implement some of the functions from Python's `math` module.

### How to add your own library

You have two options, either download a premade Lean library for that Python library(from GitHub) or write your own Lean definitions for the Python library and create Mappings for the functions you want to support.

See [Libraries](./Libraries/) for examples of how to add a library and use it.

## Testing


PastaLeanCheck (PALC) (pronounced - "pal" + "ack" like PAL Acknowledge) is the testing framework for PastaLean. It is used to check that the generated Lean code matches the expected output. This is based on the FileCheck utility from LLVM, but with some differences to make it more suitable for our use case.

To run all tests:
```bash
lake test
```

If you want to run a specific test case, you can do so with:
```bash
lake exe palc <case_file.py>
```
