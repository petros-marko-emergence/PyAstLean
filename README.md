# PyAstLean

PyAstLean is a tool that converts Python code into Lean 4.

## Usage

Build the project from the repository root:

```bash
lake build
```

## Converting Python to Lean

Use the Python wrapper `src/py2lean.py` to convert a Python file to Lean.

```bash
python3 src/py2lean.py example_scripts/commands/assignment_arith.py --target command
```

That wrapper is responsible for:

1. Reads the Python file.
2. Runs the annotation pre-pass from `src/annotate_python.py`.
3. Converts the Python AST to the JSON IR in `src/node_visitor.py`.
4. Sends the JSON task to the Lean backend.

### Low-level Lean backend

The executable defined by [py2lean.lean](/home/anirudhgupta/PyAstLean/py2lean.lean:1) is the JSON backend.

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

## Installation

To install PyAstLean as a dependency, add the following to your `lakefile.toml`:

```toml
[[require]]
name = "PyAstLean"
git = "https://github.com/Siddhartha-Gadgil/PyAstLean.git"
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

## Testing

We use `PyAstLeanCheck` (PALC) to test the generated Lean code. Its role is similar to LLVM's FileCheck.

```bash
lake test
```
