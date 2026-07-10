# TypeInfer — giving every Python value a Lean type

Python doesn't make you write types. Lean insists on them. This little library sits in the middle:
it works out a Lean type for each Python value, so the generated Lean code compiles instead of
getting stuck.

That's the whole job. It's a small, self-contained analysis — it depends only on Lean's JSON
library, nothing from the rest of PastaLean — so the code generator can use it freely.

## Why it's needed

When PastaLean can't tell what type a variable holds, it leaves the binder untyped and hopes Lean
figures it out:

```lean
def total := fun xs ↦ …    -- xs : what?
```

Lean can't. A top-level `def` resolves its parameter types *before* it looks at the body, so it
never works backwards from how `xs` is used. The result is an error like
`typeclass instance problem is stuck` or a number silently defaulting to the wrong type. TypeInfer's
job is to fill in that `xs : List Int` so the binder is typed and the code compiles.

## The one idea: a type lattice

Every value gets a `PyType`. Most are what you'd expect — `int`, `str`, `list[int]`,
`dict[str, int]`, `Optional[TreeNode]`. Two are special:

- **`unknown`** — "we don't know *yet*." It's the starting point for everything.
- **`any`** — "we found out it's more than one thing." A variable that's an `int` on one line and a
  `str` on another is `any`.

The key operation is **`join`**: given two things we've learned about the same value, what do we
know overall?

```
join unknown int   = int      -- learning a fact beats knowing nothing
join int int       = int      -- agreement changes nothing
join int bool      = int      -- Python's bool is a kind of int (True + 1 == 2)
join int str       = any      -- genuinely two types → give up on a single one
join (list int) (list unknown) = list int   -- containers combine element-by-element
```

`join` only ever moves *up* the lattice (`unknown → a real type → any`), never back down. That's
what lets the analysis loop over a function until nothing changes and be sure it will stop.

There's also **`consistent`**, which asks "can a value of type A be used where B is expected?" It's
what a gradual type system (Siek & Taha's work on mixing typed and untyped code) uses at the
boundary. `any` is consistent with everything, which is what will eventually let a boxed
"don't-know" value flow anywhere.

## Where the types come from

Two sources, both just reading the code:

**1. Annotations you already wrote.** `ofAnnotation` reads a Python type hint into a `PyType`:

| you wrote | TypeInfer reads |
|---|---|
| `list[int]`, `List[int]` | `list[int]` |
| `dict[str, int]` | `dict[str, int]` |
| `TreeNode | None`, `Optional[TreeNode]` | `Optional[TreeNode]` |
| `"ListNode"` (a forward reference) | `ListNode` |

**2. The shape of a literal.** `ofValue` reads the type off an expression when its shape gives it
away — no annotation needed:

| expression | TypeInfer reads |
|---|---|
| `0` | `int` |
| `2.0` | `float` |
| `"hi"` | `str` |
| `[0] * n` | `list[int]` |
| `{"a": 1}` | `dict[str, int]` |

Anything whose type isn't obvious from its shape — a bare name, a function call — comes back
`unknown`, and stays a plain untyped binder that Lean's own unifier resolves from the surrounding
body. TypeInfer only fills the gaps Lean can't.

Finally, **`toTypeSyntax?`** turns a known `PyType` into the actual Lean type text: `list[int]` →
`List Int`, `dict[str, int]` → `Std.HashMap String Int`, and so on. (`float` becomes `ℚ`, `ℝ`, or
`Float` depending on the numeric mode you asked for.)

## Examples

All of these compile and run through PastaLean today, producing the same answer as CPython.

### An annotation flows into the Lean type

```python
def total(xs: list[int]) -> int:
    s = 0
    for x in xs:
        s = s + x
    return s
```

`xs: list[int]` becomes:

```lean
def total := fun (xs : List Int) ↦ …
```

`total([1, 2, 3, 4])` prints `10`.

### A type read from a literal's shape — no annotation

```python
def running_max(nums: list[int]) -> list[int]:
    out = [0] * len(nums)      # [0] * n  →  out : list[int]
    best = nums[0]
    for i in range(len(nums)):
        if nums[i] > best:
            best = nums[i]
        out[i] = best
    return out
```

Nobody annotated `out`, but `[0] * len(nums)` is clearly a list of ints, so `out` is typed
`List Int` and the `out[i] = best` assignment type-checks. `running_max([3, 1, 4, 1, 5, 9, 2])`
prints `[3, 3, 4, 4, 5, 9, 9]`.

### A dictionary parameter

```python
def price_of(cart: dict[str, int], item: str) -> int:
    return cart.get(item, 0)
```

becomes:

```lean
def price_of := fun (cart : Std.HashMap String Int) ↦ fun (item : String) ↦ …
```

### A helper defined inside a function

PastaLean lifts a nested `def` out to its own top-level function, turning the variables it captures
into extra parameters. Those parameters need types — and that's exactly where an untyped binder used
to leave Lean stuck.

```python
def path_count(grid: list[list[int]]) -> int:
    rows = len(grid)
    cols = len(grid[0])

    def walk(r: int, c: int) -> int:
        if r >= rows or c >= cols:
            return 0
        if r == rows - 1 and c == cols - 1:
            return 1
        return walk(r + 1, c) + walk(r, c + 1)

    return walk(0, 0)
```

`walk` captures `rows` and `cols`, which become extra parameters when it's lifted out. They come
from `len(...)`, so their types are recovered by Lean's own unifier from how they're compared
against `Int`. A captured *list* — the case that used to leave Lean stuck — gets its element type
from its shape instead, exactly like `out` above. Either way the lifted helper is well-typed, and
`path_count([[0,0,0],[0,0,0]])` prints `3`.

## Following a type through a function

Reading a type off one expression isn't enough — the type learned in one line has to reach every
use. That's the fixpoint: seed each variable from what we know, then walk the function body over and
over, learning a bit more each pass, until nothing changes. Because we only ever `join` upward, it
always settles.

The payoff is the accumulator pattern, where the *literal is empty* and the type only appears later:

```python
def evens(n: int) -> list[int]:
    out = []                 # out : list[?]  — nothing to go on yet
    for i in range(n):
        out.append(i * 2)    # out.append(int) — now we know: out : list[int]
    return out
```

Nobody annotated `out`, and `[]` says nothing. But `out.append(i * 2)` teaches us the element type,
so `out` is ascribed `List Int`:

```lean
let mut out : List Int := []
```

That one ascription is what stops Lean defaulting the empty list's element to `ℚ` and getting stuck
on the later `out.append`. The same thing types a dictionary from its first `d[k] = v`, and a
lifted helper's captured variables from how the enclosing function uses them.

## What's here, and what's next

Today the library:

- reads a type from an **annotation** or a **literal's shape** (P0), and
- **propagates** it through a function to a fixpoint, ascribing `fun (x : T)` on parameters and
  `let mut x : T := …` on locals (P1).

Still to come, in order:

- **Across functions** — let a caller's argument types reach a callee's parameters, and a callee's
  return type reach the call site, iterated to a fixpoint over the whole module.
- **`PyAny`, the total fallback** — for the slots that stay `unknown`, box the value into a single
  runtime type that holds anything. That's what makes the transpiler handle *general* Python and
  never simply fail; the cost is that a boxed value isn't provable, so it comes with a warning and a
  `--strict-types` flag to turn the warning into an error.
- **Coercions** — insert the small conversions Python does implicitly (`bool` used as an `int`,
  unwrapping an `Optional`, projecting a tuple element).

## The files

| file | what's in it |
|---|---|
| `PyType.lean` | the `PyType` lattice: `join`, `consistent`, `elemType` |
| `Annotation.lean` | `ofAnnotation` / `toAnnotation?` — Python type hints ↔ `PyType` |
| `Value.lean` | `ofValue` — the type of a literal, read from its shape |
| `Emit.lean` | `toTypeSyntax?` — `PyType` → Lean type text |
| `Rules.lean` | `typeOfExpr` / `applyStmt` — the type of an expression, and how a statement updates what's known |
| `Solve.lean` | `inferFunction` (the fixpoint) and `stampNode` (write `_ty` back onto the IR) |

Tests are in `PastaLeanTest/TypeInfer/TestLattice.lean` and `TestInfer.lean` (unit checks on the
lattice and the rules) and `PastaLeanTest/PastaLeanCheck/Typing/` (worked programs).
