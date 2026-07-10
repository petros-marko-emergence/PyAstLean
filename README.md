# PastaLean

<img src="./src/static/logo.png" width="200" height="200" />

PastaLean is a tool that transpiles and verifies Python code into Lean 4.

For an overview of the project, see the [presentation](https://anirudhg07.github.io/presentations/pastalean/).
This work was presented at [Summer School: LeanLang for Programming 2026](https://east.emergence.ai/summerschool-july2026.html).

> PastaLean originates from "PyAstLean"(which mean Python to Lean via AST) but who doesn't love Pasta.

## Features

- Transpiles Python code to Lean 4 code.
- The tool gives 2 functions for the same function, one `provable` and one `computable`(marked with `'rn`).
- Verification of the code(using assert and contract statements) using tactics like `taste?`, `mvcgen`, etc.

## How it works?

## Install

If you would like to use this as a Library, you can install it by adding it in your `lakefile.toml`:

```toml
[[require]]
name = "PyAstLean"
scope = "siddhartha-gadgil"
rev = "v4.31.0"
```

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
pastalean serve                          # web playground + HTTP API
pastalean libraries                      # Python libs with a Lean shim
```

`translate` and `run` also accept the LLM source rewrites `-r/--redesign` (restructure for
provability) and `-c/--contracts` (insert Requires/Ensures/Invariant). Both write the transformed
program to a sibling `.py` so you can read what the model produced.

## HTTP API

```bash
pastalean serve                 # reachable from the LAN; prints this machine's URL
pastalean serve --no-ip         # localhost only
```

- Opening the printed URL opens a small web playground.
- Paste Python and press **Translate** to see generated Lean with syntax highlighting and compile errors, if any.
- Press **Run both** to execute the Python and Lean on the same standard input and verify they agree.
- **Insert contracts** runs the `--contracts` LLM pre-pass and shows the annotated Python in its own box, ready to use as the source.
- Provider, API key, model, and goal are available under **Settings**.
- An API key entered in the UI stays in that browser and is sent with each request.
- The server forwards the key to the provider and does not store or log it.
- Leave the field blank to use the server's environment variables such as `OPENAI_API_KEY` or `GEMINI_API_KEY`.
- The machine-readable API lives at **`/api`** and `/openapi.json`.
- Those endpoints are authoritative; the table below is only a summary.

### Examples

In one shell:

```bash
uv run pastalean serve
```

In another shell you can test the API with `curl`:

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

## Acknowledgements

This project was made possible by the support of collaboration of IISc Bengaluru and Emergence AI.