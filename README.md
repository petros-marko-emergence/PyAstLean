# PastaLean

PastaLean is a tool that converts Python code into Lean 4.

PastaLean originates from "PyAstLean"(which mean Python to Lean via AST) but who doesn't love Pasta.

## Install

Build the Lean side from the repository root, then install the Python package:

```bash
lake build
uv pip install -e '.[server]'      # drop [server] if you don't want the HTTP API
```

That puts a `pastalean` command on your PATH. `python -m pastalean` works too, and takes the
same arguments.

## Command line

```bash
pastalean translate example_scripts/commands/assignment_arith.py   # Python -> Lean, on stdout
pastalean check     prog.py                                        # translate, then `lake env lean`
pastalean run       prog.py < input.txt                            # translate, compile, execute
pastalean json      prog.py                                        # dump the intermediate JSON IR
pastalean batch     example_scripts/commands -o out/ --check       # many files, one warm backend
pastalean serve     --port 8000                                    # HTTP API
pastalean libraries                                                # Python libs with a Lean shim
```

Flags shared by `translate`, `check`, `run`, `json`, and `batch`:

| Flag | Meaning |
| --- | --- |
| `--target command\|term` | Top-level declarations (default) or a single expression. |
| `--mode prove\|run\|both` | Exact ℚ/ℝ (provable), `Float` (runnable), or both in one file (default). |
| `--strict` | Fail on unsupported constructs instead of emitting `pyUnsupported(...)` placeholders. |
| `--no-prove-asserts` | Leave each assert as `:= by taste?` rather than searching for a proof. |
| `-v` | Dump the intermediate JSON IR and Lean syntax. |

`translate`, `check`, and `run` also accept the LLM source rewrites `-r/--redesign` (restructure
for provability) and `-c/--contracts` (insert Requires/Ensures/Invariant). Both write the
transformed program to a sibling `.py` so you can read what the model produced.

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
