# PastaLean

<div align="center">
<img src="./src/static/logo.png" width="200" height="200" />
<p>Pasta for All - Python - in Lean4</p>
</div>

PastaLean is a tool that transpiles and verifies Python code into Lean 4. As the name suggests, this tool is not just for a small use-case but for all(not actually all, but as much as possible) Python code and it's behaviors. Modelling Python code in Lean 4 can be extremely annoying since it's a dynamically typed and, well, Python trying to make life easy for everyday users, harder for us.

For an overview of the project, see this [presentation](https://anirudhg07.github.io/presentations/pastalean/).
This work was presented at [Summer School: LeanLang for Programming 2026](https://east.emergence.ai/summerschool-july2026.html).

> PastaLean originates from "PyAstLean"(which mean Python to Lean via AST). Who doesn't love Pasta. It's Pasta for all, which if you didn't yet guess, comes from the Lean's "for all" logo.

## Table of Contents

- [Features](#features)
- [How it works?](#how-it-works)
- [Libraries](#libraries)
    - [How to add your own library](#how-to-add-your-own-library)
- [Install](#install)
- [Using PastaLean everyday](#using-pastalean-everyday)
    - [Command line](#command-line)
    - [HTTP API](#http-api)
    - [Python API](#python-api)
- [Testing](#testing)

## Features

- Transpiles Python code to Lean 4 code.
- The tool gives 2 functions for the same piece of code, one `provable` and one `computable`(marked with `'rn`).
- These functions have subtle differences in their implementation, for their respective purposes as you can guess.
- Verification of the code(using assert and contract statements) using tactics like `taste?`, `mvcgen`, etc.

## How it works?

A nice explanation of how PastaLean works can be found in the [presentation](https://anirudhg07.github.io/presentations/pastalean/). Let's give a brief overview here. 

### Some Unique Python Features and How we handle them

Python has some unique features that make it hard to model in Lean because of the differences in the type systems. Not just that, but also it's own special features which we are forced to model in Lean. Let's take a look at some of them:

<details><summary>Dynamic Typing</summary>

This has been the toughest one. The answer to this I found was something called `Gradual Typing` from [Siek and Taha](https://dl.acm.org/doi/10.1145/100528.100531). The idea is to have a special type called `PyAny` which can be used to model any type in Lean. This is a very powerful idea and we use it to model Python's dynamic typing in Lean.

We constructed a [TypeInfer](./TypeInfer/) engine which can infer the types of the variables in the Python code, made a Lattice following the rules of gradual typing and fine-tuning it for Python's type system.
For example: `int` and `bool` in Python can be used interchangeably in some cases, so we have to make sure that the type inference engine can handle this. `PyAny` has given us a lot of flexibility in modelling Python's dynamic typing in Lean.


</details>

<details><summary>Multiple Return Types</summary>

This is another tough one. Python allows for a function to return different types based on the input arguments. Thanks to `PyAny`, we can return the type `PyAny` when multiple return types are present.
In case of single type returns, we can return the specific type, as we should and someone would expect.

*Why don't we make something like `Int | String` Union type?*
Well, we can do that, but then Python doesn't even follow that. A function saying it will return `int` in the signature can return a `str` in some cases. Dealing with that is a nightmare, rather simply returning `PyAny` is a better idea. It might not be precise, but it is sound, and it works.

</details>

<details><summary>Mutations, not just Values but also Types</summary>

We use simply `do` notation to model the mutations in Lean. As long as the Type doesn't change, we can model without any fancy tricks.
However since Python allows for the type of a variable to change during the execution of a program, we have to make sure that the type inference engine can handle this. Thanks to the `TypeInfer` engine, we can handle this by keeping track of the types of the variables in the program and updating them as needed.
The main idea is, do a `type inference` analysis on the generated Lean code. If you find that Type changes, the new Type of the variable becomes `PyAny` and we have to make sure that functions which apply on `Int` work on it. 
For Example, if `x: PyAny`, but `x = 5`, then `x + 1` will perform `PyAny -> Int`, perform the operation(`Int` -> `Int`)(here it's addition), then convert the result back to `PyAny`. This is done by Casting `PyAny` back and forth to the required type. Since `PyAny` is at the top of the type hierarchy, we can always cast it to any type. 

</details>

<details><summary>What about operators with no Type pre-given but work on different types</summary>

Yes, for example:
```python
def add(x,y):
    return x+y
```
This is a very hard challenge to model. If no Types are given, or can be inferred directly, we have to make sure that the function works on all types, for a sound inferece. Hence we use `PyAny` as the type of the arguments and return type. 

This allows you to compute `add(1,2)`, `add("Hello", "World")`, etc. by the mechanism of casting `PyAny` to the required type, performing the operation, then casting back to `PyAny`. 

</details>

<details><summary>Default Arguments</summary>

Yes, we support it. 

```lean
def add (a : Int) (b : Int := (10 : Int)) :=
  a +ₚ b
```

Moreover, if the input types are not given, we can infer them using the `TypeInfer` engine for other arguments as well. Thanks for clarifying the types of the arguments, otherwise you only get `PyAny` as the type of the arguments and return type.

</details>

<details><summary>Same Syntax, Different Semantics for Different Types</summary>

We use TypeClasses and instances on different types, to model this. Best example is the `len` function.

```python
len([1, 2, 3]) # returns 3
len("Hello") # returns 5
len({"key": "value"}) # returns 1
```

We create a TypeClass called `PyLen` under which instances for Types like `List`, `String`, `Dict` are created. Each instance has it's own implementation of the `len` function. See [PyLen](./PastaLean/PyAPI/CommonProtocols/Length.lean) for more details.

Similarly other functions behaving differently for different types but have the same syntax, are modelled using TypeClasses and instances.

</details>

<details><summary>Object Oriented Programming</summary>

OOP is handled like namespaces. The `__init__` function is used to create the structure of the class, and the methods are added as functions under the namespace of the class. For example, a class `A` with a method `foo` will be modelled as a structure `A` with a function `foo` under the namespace of `A`. The methods can be called using the dot notation, like `A.foo()`.

We donot support a lot of OOP features like polymorphism, very basic inheritance, etc. If you try jipsies with OOP, which python allows but not standard/best practise of OOP, the tool might not work as expected. We are working on improving the OOP support in the tool.

</details>

<details><summary>Exceptional Handling and IO</summary>

Exceptional Handling are handled using the `PyExcept` Monad.

</details>


More details will be shared SOON.

## Libraries

Python libraries can be supported in PastaLean by writing Lean definitions that correspond to the Python library's API. These definitions can be made by implementing the necessary translation logic in the Lean backend, then added to PastaLean by creating a mapping using `Mapping.lean` which is simply a map from python name for a function to Your Lean definition.

For example, see [math](./Libraries/math/) library, which uses Mathlib to implement some of the functions from Python's `math` module.

### How to add your own library

You have two options, either download a premade Lean library for that Python library(from GitHub) or write your own Lean definitions for the Python library and create Mappings for the functions you want to support.

See [Libraries](./Libraries/) for examples of how to add a library and use it.

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

## Using PastaLean everyday

We give a Python API for developers to run a backend server and translate Python to Lean on the fly. We use `uv` for handling the Python environment management — it installs the project, it's binaries, `.venv/` on first use, so there is no separate install step:

```bash
uv sync
uv run pastalean translate prog.py
```

or install it yourself, which additionally puts `pastalean` on your PATH:

```bash
uv pip install -e '.[server]' # drop [server] if you don't want the HTTP API
pastalean translate prog.py
```

### Command line

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

### HTTP API

We provide an HTTP API on default port `6789`:

```bash
pastalean serve                 # reachable from the LAN; prints this machine's URL
pastalean serve --no-ip         # localhost only
```

This provides the below features for you to use PastaLean -

*Web UI*:
- Paste Python and press **Translate** to see generated Lean with syntax highlighting and compile errors, if any.
- **Insert contracts** runs the `--contracts` LLM pre-pass and shows the annotated Python in its own box, ready to use as the source.
- Provide an API key and select model to use for contracts. You can also write a custom prompt as a goal for LLM for what you want the contracts to achieve. The settings are available under **Settings**.
- You can see the generated Lean code and the contracts in their own boxes, with syntax highlighting and compile errors, if any.

*HTTP API*:
In one shell, you can run:

```bash
uv run pastalean serve
```

In another shell you can test the API with `curl`:

```bash
curl -s localhost:6789/translate -H 'content-type: application/json' \
     -d '{"source": "def f(x: int) -> int:\n    return x + 1\n"}'

curl -s localhost:6789/run -H 'content-type: application/json' \
     -d '{"source": "def main():\n    print(int(input()) + 10)\n\nif __name__ == \"__main__\":\n    main()\n",
          "stdin": "32\n", "mode": "run"}'      # -> {"stdout": "42\n", "exit_code": 0, ...}
```

Invalid Python returns HTTP 400. One Lean backend serves every request and translation drives
process-wide state, so requests are serialised behind a lock — this is a single-worker service by
construction.

### Python API

You can also use PastaLean from Python code after downloading this as a python package in your virtual environment(though you would need to install the Lean side as well, see [Install](#install)):

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

Booting the backend imports Mathlib(the first run will take a lot of time, subsequent are faster), so a `Session` is much faster than one process per file. `pastalean.compile_check` and `pastalean.run_program` take Lean text
and shell out to `lake env lean`.

## Testing

PastaLeanCheck (PALC) (pronounced - "pal" + "ack" like PAL Acknowledge) is the testing framework for PastaLean. It is used to check that the generated Lean code matches the expected output. 

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