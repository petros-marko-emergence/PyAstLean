# Design choices in PastaLean

This document records the non-obvious decisions behind PastaLean — the Python → Lean 4
transpiler — and, for each, why the alternatives we considered were worse. It is meant to be
read top to bottom: the later choices only make sense once the first one is on the table.

The through-line: **we translate the part of Python that has a stable mathematical meaning, and
we make the Lean elaborator the judge of whether we got it right.** Almost every decision below
is downstream of that.

---

## 1. We target the static, "logic" subset of Python — not all of it

**The choice.** PastaLean handles ints, floats, strings, lists, dicts, sets, tuples, loops,
comprehensions, functions, classes, and exceptions — the "logic side of data science" and
competitive-programming code. Dynamic and reflective Python (`yield`, `async`/`await`, `with`,
walrus `:=`, `global`/`nonlocal`, monkey-patching, `eval`, most of the runtime stdlib like
`os`/`random`/`threading`) is **out of scope by design**. Anything unsupported degrades to a
single `pyUnsupported("<original source>")` placeholder (`PyAPI/Core.lean`), flagged by a linter,
so the rest of the file still compiles. `--strict` turns those degradations into hard errors
instead. The catalogue lives in `docs/syntax-gaps.md`.

**Why.** Lean 4 is a total, statically-typed language with no top-level mutation and no
untyped "any". The whole value proposition is that the output *type-checks* and, where pure, is
*provable*. A construct only survives the trip if it has a meaning Lean can represent. The
subset we chose is exactly the subset where a faithful Lean model exists.

**Why not "support everything".** Python's dynamic features don't have a single static meaning
to preserve — `yield`'s laziness, `eval`'s runtime code, duck-typed attribute access, exceptions
used as control flow across arbitrary types. Modelling them would mean either (a) an interpreter
embedded in Lean that reproduces CPython's runtime (at which point you've written a slow CPython,
not a transpiler, and lost all provability), or (b) silently emitting Lean that *looks* right but
diverges on the corners. We'd rather refuse loudly (`pyUnsupported`) than translate wrongly.
Every hour spent chasing `async` is an hour not spent making the provable core airtight.

---

## 2. An AST transpiler — not an LLM, not text munging

**The choice.** We parse Python to its real AST and walk it. Translation is a total function
from AST node to Lean syntax: the same node always produces the same Lean, forever.

**Why not "ask an LLM to translate".** This is the tempting shortcut and we deliberately reject
it for the core translation:

- **It hallucinates.** An LLM will silently change `//` to `/`, drop an off-by-one, or invent a
  library call. There is no ground truth telling you it was wrong.
- **It isn't reproducible or auditable.** Re-run it and the output drifts. You can't point at a
  line of a mapping table and say "*this* is why `append` became `pyAppend`."
- **It doesn't compose.** It works on a toy snippet and falls apart on a 300-line program,
  because there's no structural guarantee tying statement 200 to statement 5.

With an AST transpiler the **Lean elaborator is the oracle**: if the emitted Lean type-checks,
the translation is at least type-correct against a runtime we wrote on purpose. The LLM still
earns its keep — but only for *proposing contracts/specs* (`--contracts`), where a wrong guess is
harmless because Lean refuses to close the proof.

**Why not regex / text substitution.** Python's grammar is not regular. Indentation-sensitive
blocks, nested comprehensions, operator precedence, and scoping cannot be recovered by string
replacement without effectively rebuilding a parser. We'd be writing a worse AST, badly.

**Why the AST and not the token stream.** Tokens have lost the structure (what's a loop body,
what's a function's scope) that we need to make decisions like "does this function mutate a
variable" or "is this expression pure". The AST carries exactly that structure.

---

## 3. A JSON-lines IR streamed to one persistent Lean backend

**The choice.** The Python side lowers each node to a small JSON object `{"node_type": "...", ...}`.
The Python driver (`src/transpile/driver.py`) boots **one** long-lived Lean process and streams it
**one line-delimited JSON request per top-level statement** — `{"task":"translate","ast":...}\n`
— reading one response line back. The Lean backend turns each JSON node into Lean `Syntax`.

**Why a JSON IR at all — why not have Python emit Lean text directly?** Because the two hard
halves of the job want different languages. *Parsing and analysing Python* is easy in Python
(the `ast`/`libcst` libraries are right there). *Producing correct Lean syntax and checking it*
must happen in Lean, because only Lean knows Lean's grammar, notation, and elaboration. JSON is
the neutral seam between them: Python decides *what* each node is; Lean decides *how* it renders
and whether it checks. Emitting Lean text from Python would mean re-implementing Lean's pretty-
printer and hoping it stays in sync with the compiler — a permanent maintenance tax.

**Why line-delimited JSON, and why per-statement.** A program is a sequence of independent
top-level statements, so the natural unit of work is one statement. Line-delimited JSON makes
the protocol trivially streamable: write a line, flush, read a line. It also isolates failures —
one bad statement doesn't poison the batch, and `--verbose` can dump the IR and the Lean syntax
for exactly that node.

**Why one persistent backend instead of one process per node.** Booting a Lean process that
imports Mathlib + the PastaLean runtime costs seconds. Doing that per statement would make a
medium program take minutes. We pay the import cost **once** and then every statement is a cheap
round-trip on stdin/stdout. (Mutually-recursive functions are the one exception — they're
grouped into a single synthetic `Module` request so Lean sees them together.)

**Why not one giant blob for the whole file.** Per-statement keeps memory bounded, gives precise
per-node error attribution, and lets the driver thread top-level state between statements
(Lean has no top-level mutation, so `x = x + 1` at module scope has to be re-threaded — see the
`toplevel_state` pass).

---

## 4. Annotate the Python *before* translating

**The choice.** Before any Lean is produced, a pre-pass (`src/annotate_python.py`, built on
`libcst` + `pyrefly` for type stubs) rewrites the Python *source* to add explicit type
annotations to parameters, returns, and variables, using flow analysis to infer what the user
left implicit. A second family of passes in `src/transpile/driver.py` then stamps the JSON AST with derived
facts: which names are mutated, which functions are real-valued (`_real_fn`), and each node's
`effect_mode` (`"except"` / `"io"`).

**Why.** Lean is statically typed; Python often isn't annotated. Somewhere between the two, every
binder needs a type. Recovering it *once*, up front, where we have the whole function in view and
can run real type inference, is far more reliable than guessing locally in the code generator
while emitting syntax. The annotation pass is where "what type is this?" is answered; the code
generator is left to answer only "what syntax does this become?".

**Why a separate pass and not inline in the generator.** Type inference is global (a parameter's
type may only be pinned by how it's used three lines down); code generation is local (one node at
a time). Mixing them would force the generator to backtrack. Splitting them keeps each pass
simple: one does whole-function reasoning, the other does a straight structural walk. It also
means the *effect* analysis (does this raise? does this do IO? is this real-valued?) is computed
once and carried on the node, rather than re-derived every place we need it.

---

## 5. Runtime vs. code generator — and libraries as *data*, not code

**The choice.** The Lean side is split by a hard line:

- `PastaLean/PyAPI/` is the **runtime**: Lean implementations of *what a Python operation does*
  (`pyAppend`, `pyRange`, the operators `+ₚ -ₚ *ₚ`, the container protocols).
- `PastaLean/PyGens/` is the **code generator**: *which Lean syntax each AST node emits.*
- Method/library names are wired across the seam by *tables*: `Attributes.lean`'s
  `pythonMethodMap` (`"append"` → `pyAppend`), and each library's `Mapping.lean`
  (`Libraries/numpy/Mapping.lean`: `"dot"` → `` ``pyNumpyDot ``).

**Why the runtime/codegen split.** These are two genuinely different questions. "What does
`list.append` *mean*?" is a semantics question with one answer, reused everywhere. "How does an
`Attribute` call node render?" is a syntax question. Keeping behaviour in `PyAPI` means a bug in
Python's semantics is fixed in *one* place and every call site inherits the fix; keeping syntax
decisions in `PyGens` means changing how a node looks never risks changing what it means. When you
sit down to work, you always know which side of the line your change is on.

**Why library support is a mapping table and not bespoke code.** Adding `numpy.std` should be:
write `pyNumpyStd` in the runtime, add one line `"std" => ``pyNumpyStd` to the mapping. No changes
to the parser, the IR, or the generator. Libraries become *data* the dispatcher reads
(`Libraries/Registry.lean` on the Lean side; `SUPPORTED_LIBRARY_IMPORTS` / `_supported_library_root`
on the Python side, so `scipy.special` is known to belong to supported `scipy`). This is what makes
"add a library" a bounded, mechanical task instead of a surgery.

**Why not implement library functions inside the generator.** Then every function would entangle
"what it computes" with "how the call site is emitted", the two would drift, and each new library
would touch the codegen core. The table keeps the blast radius of a new library to two files.

---

## 6. Numbers: exact by default, approximate on request

This is the subtlest choice, because Python's one `float` type has to become one of *three*
different Lean types depending on what you want to do with it.

**The choice.** A `--mode` flag (`prove | run | both`, default `both`) selects the numeric
semantics; internally this is the string `"exact"` vs `"approx"` (default `"exact"`), threaded to
the backend and stored in `numericModeRef`:

| Python `float` | Lean type | When |
|---|---|---|
| exact mode (`prove`) | `ℚ` (`Rat`) | default — exact, computable, an ordered field |
| exact mode, transcendental context | `ℝ` (`Real`), `noncomputable` | function transitively uses `math.exp`/`sqrt`/… |
| approx mode (`run`) | `Float` (IEEE 754) | fast, actually runnable |

`--mode both` emits *both* — the provable version under its name and a runnable twin (suffixed).

**Why `ℚ` and not `Float` by default.** `Float` is IEEE 754: it is not associative, not a ring,
and `0.1 + 0.2 ≠ 0.3`. You cannot prove anything about it — `ring`, `nlinarith`, and friends all
need the algebraic laws that floats break. `ℚ` (`Rat`) *is* an ordered field: it is exact, it is
still **computable** (so the program can run), and it satisfies the axioms the proof tactics rely
on. For "the logic side of data science", exact rational arithmetic is both runnable and
provable, so it's the right default.

**Why `ℝ` only when forced, and why `noncomputable`.** The moment a function reaches for a genuine
transcendental (`exp`, `sqrt`, `sin`), `ℚ` can't represent the result and we must move to `ℝ` to
keep the mathematics honest and provable. But `ℝ` in Lean is `noncomputable` — you can prove
theorems over it, you can't *run* it. So we don't pay that price globally: a flow analysis stamps
only the functions that actually need it (`_real_fn` / `realContextRef`), and *within* such a
function every `float` lowers uniformly to `ℝ` so the types line up. Everything else stays the
cheap, runnable `ℚ`.

**Why keep `Float` at all, then.** Because sometimes you just want to *run* the thing fast on real
data, and you don't care about a proof. `--mode run` gives you honest IEEE floats and honest
speed. `--mode both` is the default precisely because you usually want a provable artifact *and* a
runnable one from the same source, without choosing up front.

**Why not pick one and force it.** A single choice loses half the point. Float-only throws away
provability; ℝ-only throws away execution; ℚ-only can't express transcendentals. The mode flag
lets the *use* decide, and the default (`both` → exact math is the primary, runnable is the twin)
matches the project's bias toward provability without giving up the ability to run.

---

## 7. The effect ladder: pure term → `Id.run do` → `Except` → `IO`

**The choice.** A function is lowered to the *least powerful* shape that can express it. In order
of increasing power:

1. **Pure term** — e.g. `def dist2 (a b : ℚ) := (a - b)^2`. No effects at all.
2. **`Id.run do` block** — for local mutation / loops (`let mut`, `for`). Still pure (the `Id`
   monad is the identity), just written imperatively so it stays *computable* and reads like the
   original Python.
3. **`Except` monad** — for `raise` / `try` / `except`. In exact mode with no real IO this is the
   *pure* `PyExceptId` (`ExceptT PyException Id`); with real IO it's `PyExcept`
   (`ExceptT PyException IO`).
4. **`IO`** — for `input()` (and `print()` in run mode).

The decision is driven by predicates over the annotated node (`jsonUsesExceptionEffect`,
`jsonUsesIOEffect`, `jsonUsesMonadicEffect` in `PyGens/Core/Utils.lean`), reading the `effect_mode`
stamped by the Python passes.

**Why climb only as far as needed — why prefer the pure end.** *Provability lives at the bottom
of the ladder.* A bare term can be stated and proved about directly (`taste?`). An `Id.run do`
block is still pure, so it's provable too, just with the `mvcgen` Hoare-triple machinery instead
of `ring`/`grind`. Once you're in `IO`, there is nothing to prove — `IO` actions are opaque; their
result depends on the outside world. So every rung you climb *costs you proof power*. We climb
exactly as far as the code forces us and no further. The design doc puts it bluntly: `print`,
`raise`, and mutation "cost you the proof."

**Why `Id.run do` rather than keeping everything a single expression.** Some Python is genuinely
imperative — a loop that accumulates into a mutable variable. Contorting that into a fold or
recursion would produce Lean that no longer resembles the source and is harder to relate back to
the Python. `Id.run do` lets us keep the imperative shape *and* stay pure (because `Id` is the
identity monad), which is the best of both: it runs, and it's still provable via `mvcgen`.

**Why a *pure* exception monad (`PyExceptId`) at all.** A `try`/`except` that does no IO — pure
input validation that raises `ValueError` — has no reason to be dragged into `IO`. Keeping it in
`ExceptT PyException Id` means the function is still a pure value we can prove things about (e.g.
"*it raises exactly when the inputs are mismatched*"). Collapsing all exceptions into `IO` would
needlessly forfeit that.

**When does each trigger?** `input()` → always `IO`. `print()` → `IO` only in run mode; in *exact/
prove* mode it's a **no-op** (see §8). `raise`/`try` → `Except`. `let mut`/`for` with mutation →
`Id.run do`. Anything else → a pure term.

**Effects are infectious — and that's intended.** If `f` raises and `g` calls `f`, then `g` is
also in the `Except` monad, and so is everything up the call chain. This isn't an accident to be
worked around; it's the type system telling the truth about where a program stops being pure. The
`--redesign` flag exists precisely to help *push those effects to the edges* so the provable core
stays as large as possible.

---

## 8. Pin the monad at the binder: `... : PyExcept _`

**The choice.** When a function needs the exception (or IO) monad, the code generator writes the
monad **into the function's declared return type** — `def f (...) : PyExcept α := ...` (or
`PyExceptId α`, or `IO α`) — chosen in `PyGens/UseCases/FuncDef.lean` from the effect predicates.
The ascription is the load-bearing part; the body is written in `do`-notation against it.

**Why annotate the type explicitly instead of letting Lean infer it.** Monad inference in Lean is
driven by expected types, not guessed from the body. In a `do` block, `pure x`, `throw e`, and a
bare `x` are all polymorphic over the monad — Lean cannot know *which* monad you mean unless
something pins it. Writing `: PyExcept α` at the binder is that pin: it tells the elaborator "this
whole `do` block lives in `ExceptT PyException IO`", and then every `throw`/`pure`/bind inside
resolves against it. Without the ascription the body is ambiguous and elaboration fails (or, worse,
picks a monad we didn't mean).

**Why put it on the return type specifically.** It's the one place that governs the entire body
and every `return`/`raise` path at once, and it's exactly what callers see — so the infectiousness
of §7 is expressed in the *type*, where the type-checker can enforce it. A caller that forgets to
bind an `Except`-returning function gets a type error, not a silent bug.

**Why the exact-mode distinction (`PyExceptId` vs `PyExcept`) is decided here.** This binder is
the single spot where we know both facts at once — "does this raise?" and "does this do real IO?"
— so it's where the precedence rule lives: exceptions outrank IO, and in exact mode an
exception-only function gets the *pure* `PyExceptId` so it stays provable. Centralising that
decision at the return type keeps it consistent across every call and every proof.

---

## 9. IO stays at the edge — and `print` is a no-op when proving

**The choice.** A Lean program's entry point is `IO Unit`, so genuine effects have to live in
`IO` somewhere. We keep that surface as small as possible, and we make one deliberate asymmetry:
in **exact/prove mode, `print()` is a no-op**, not an `IO` action (`input()` is always `IO`).

**Why print-as-no-op in prove mode.** Printing has no mathematical meaning — it doesn't change any
value, it just emits text. In a mode whose entire purpose is to produce a *provable* artifact,
letting a stray `print` drag an otherwise-pure function into `IO` would destroy its provability for
zero semantic gain. So when we're proving, we drop the print. In `run` mode, where you actually
want to see output, `print` is real `IO` again. `input()` is different — it *introduces a value*
from outside, so it genuinely has to be `IO` in both modes.

**Why hoist/inline IO rather than let it leak.** An expression like `int(input()) + 5` has an `IO`
sub-term sitting in a pure position. Rather than smear `IO` across the whole surrounding
expression, we hoist the `← input()` await to where it's bound and inline the pure remainder
(`inlineIOTerm`, guarded by the `jsonUsesIOEffect` predicates). The effect is *localised* to the
one spot that truly needs it, so the surrounding code stays as pure as possible — the same
"climb only as far as needed" principle as §7, applied inside a single expression.

---

## 10. Loops and branches become native Lean `do` blocks — not folds

**The choice.** A Python `for x in xs:` lowers to a Lean `for x in xs do ...`; a `while` to
`while cond do ...`; an `if` in statement position to an imperative `if`. All of this lives inside
the enclosing function's `do` block (`Id.run do` for a pure function). We do *not* rewrite loops
into `List.foldl`/recursion.

**Why.** Two reasons, both about staying faithful. First, the output should *read* like the Python
— a reviewer can line up the loop with the source. Second, and more important, an `Id.run do` loop
is exactly the shape `mvcgen` reasons about with loop invariants; a hand-rolled fold would still be
pure but would force us to re-derive the invariant machinery ourselves. Native `do` gives us both
readability and a proof story for free.

**Why not folds/recursion.** They obscure the source, and they move loop-carried state into
accumulator arguments that no longer match the Python variable names — which makes both the
generated code and any proof about it harder to relate back to the original.

**Why the `if` is *dependent* (`if h : cond then ... else ...`).** The generator binds the branch
condition as a hypothesis `h`, so inside the then-branch a proof has `h : cond` available and the
else-branch has `¬cond`. It costs nothing at runtime and hands the prover the fact it would
otherwise have to reconstruct. The hypothesis name is reserved with `freshName` *before* the
branches are lowered, so a nested `if` gets `h_1` rather than shadowing the outer `h`.

## 11. Top-level state threading: module globals as state transformers

This is the single biggest structural mismatch between the two languages, and the most involved
piece of the pipeline (`src/toplevel_state.py`).

**The problem.** Python runs top-level statements in order and mutates module globals:
`x = 0; x = x + 1; if cond: x = 5`. Lean has no top-level statement execution and no mutable
globals — a top-level `def` is a single immutable binding, and you can't redefine it.

**The choice.** Each top-level block that mutates globals (`if`/`for`/`while`/`match`/`try`) is
treated as a **state transformer over the names it mutates**. A whole-module pass computes, for
each block, the set of globals it writes that already have a value, then the backend emits that
block as `def __py_block_N := Id.run do let mut x := x₀; <block>; return (x, ...)` and *re-exports*
each mutated name as a fresh `def x := __py_block_N` (or a projection when several names change).
The value each name feeds *in* is versioned (`x₀`) so the clean name `x` stays free to be the
re-export. A top-level `for` becomes a `List.foldl` over the tuple of threaded names.

**Why do the analysis in Python and the emission in Lean.** The analysis is whole-module name flow
— "which later statement reads a name this block wrote?" — which is exactly what Python's AST
tooling is good at, and it needs to see the entire module at once. The Lean backend, by contrast,
sees one statement at a time (see §3), so it can't do this reasoning itself; it just consumes the
annotations. This is the same split as §4, applied to module-level control flow.

**Why re-export as fresh `def`s instead of one big `do` for the whole module.** Because translated
top-level names must stay usable *declarations* — later functions and statements refer to them by
name. Collapsing the module into one `do` block would bury those names inside a local scope where
nothing else could reach them. Only pure blocks are allowed here (`Id.run`); a top-level block that
does IO or can raise is rejected, because there's no pure state-transformer story for it.

## 12. Verified `while` loops: the `pyWhile` combinator

**The problem.** An ordinary Python `while` lowers, through Lean's `do`-notation, to
`Loop.forIn` → the **`partial`** `whileM` fixpoint. `partial` definitions are opaque: they have no
equational lemma, so *nothing can be proved about them directly*. Fine for running, useless for
verification.

**The choice.** When a `while` carries a contract (`Invariant(...)` + `Decreases(measure)`
markers), it is lowered instead to a **`pyWhile` combinator** — a fuel-bounded, structurally
recursive (hence total) function in `PastaLean/PyVerify/PyWhile.lean`, driven by the measure as
fuel. It ships with `pyWhile_correct`, the standard Hoare while-rule: from an invariant preserved
by each step, a measure that strictly decreases, and an exit condition, conclude the postcondition.
The backend emits the loop as `pyWhile μ c body s₀` plus a `@[spec]` theorem discharged by
`pyWhile_correct`. The runnable twin still uses the real (opaque) `while`.

**Why a combinator instead of native `while`.** Because "provable" and "runnable" want opposite
things here: native `while` runs but can't be reasoned about; `pyWhile` can be reasoned about
because it's total and has `pyWhile_correct`. Rather than choose, we emit the total combinator for
the *prove* artifact and keep the native loop for the *run* twin — the same exact-vs-approx split
as §6, applied to iteration.

## 13. The smaller control-flow lowerings

Each of these is a small decision with a clear "why", collected here:

- **`if`-hoisting for partial assignment.** If a name is assigned in only some branches of an `if`
  and read afterward, it's pre-declared `let mut name := default` *before* the `if`, so both
  branches reassign one enclosing mutable rather than each trying to introduce it. Branch-local
  names keep their own scope. This is what makes "assign in the `then`, use it later" work at all
  in a language where a branch can't leak a binding to its continuation.
- **`break`/`continue`** map to Lean's native `do` `break`/`continue`. Python's `for…else` /
  `while…else` is implemented with a synthesized `let mut broke := false` flag set before `break`,
  with the `else` body guarded by `if !broke` after the loop.
- **`match`** uses a real Lean `match` when every case is a plain structural pattern; anything with
  guards or fall-through lowers to nested `if`/`else` instead. We prefer the native `match` because
  it's exhaustive-checked and readable, but not every Python pattern maps to one, so the `if`-chain
  is the honest fallback. (Class patterns, mapping patterns, and >2-element sequence patterns are
  not supported — they error rather than miscompile.)
- **Augmented assignment (`x += 1`)** reuses the *same* operator typeclasses as binary ops
  (`+ₚ`, `*ₚ`, …, see §18) and emits a reassignment `x := x +ₚ 1`. `self.x += v` and `a[i] += v`
  rebuild the container/record, mirroring the value-semantics of §15. One operator lowering serves
  both `a + b` and `a += b`.
- **Tuple unpacking** (`a, b = b, a`, `for a, b in zip(...)`) binds the RHS to a temp first (so a
  swap is simultaneous), then destructures — with `Prod.fst/.snd` for tuple/call sources and
  `pyGetItem` for list sources. The bindings are emitted as flat sibling statements, not a nested
  `do`, so the unpacked names stay in scope for the rest of the block.
- **Scope tracking** (`varNames`, `withFixedVariables`, `hasVar`/`addVar`, `freshName` in
  `Codegen.lean`). The generator tracks which names are already bound, because that single fact
  decides everything above: a name not yet in scope needs `let mut name := ...` (fresh declaration);
  a name already in scope needs `name := ...` (reassignment). `withFixedVariables` gives each branch
  and loop body its own scope so names first bound inside don't leak out and collide.

## 14. Classes become a structure plus namespaced defs

**The choice.** A Python `class C` becomes a Lean `structure C` (its fields) plus a set of
top-level `def C.method` functions; `self` is just the structure value, passed as the method's
first parameter typed `self : C`. Fields are collected Python-side from both class-level
assignments and every `self.x = ...` in the method bodies. `obj.method(args)` then resolves by
Lean's ordinary dot-notation to `C.method obj args`.

**Why a structure + free functions, not a class/object encoding.** Lean *has* structures and
dot-notation; a Python method is, semantically, a function whose first argument is the receiver,
which is exactly `def C.method (self : C) ...`. This is the lowest-friction mapping — it reuses
Lean's own name resolution (`obj.method` "just works"), it keeps methods as ordinary provable
functions, and it avoids inventing an object system on top of Lean's. Collecting fields from
`self.x = ...` assignments (rather than requiring class-level declarations) matches how Python
programmers actually write classes, where fields materialise in `__init__`.

**Why not model Python objects as dictionaries.** A dict-of-attributes would throw away all the
static typing — every field access would be an untyped lookup, nothing would be provable, and it
would reintroduce exactly the dynamic behaviour §1 exists to avoid. A `structure` keeps each field
typed and each method a real function.

## 15. Method mutation under value semantics

**The problem.** `self.x = 5` mutates an object in place in Python. Lean structures are immutable
values.

**The choice.** `self.x = rhs` inside a method lowers to a functional record update
`self := { self with x := rhs }`. A method that mutates `self` is wrapped as
`Id.run do let mut self := self; <body>; return self` — it *returns the rebuilt object*. At the
call site, a mutating call as a statement reassigns the receiver: `obj.m(args)` becomes
`obj := C.m obj args`. Using a mutating method as an *expression* is a hard error, with a message
telling you to call it on its own line.

**Why value semantics (rebuild-and-return) rather than simulating references.** Real reference
semantics would need a heap/`ST`/`IORef` model threaded through the whole program — which would
drag otherwise-pure classes into a stateful monad and destroy their provability (§7), all to
support object aliasing that this class of programs rarely relies on. Rebuilding the value keeps
methods pure and provable. The cost is honest and *documented*: two names bound to "the same"
object don't alias, so a mutation through one isn't seen by the other. We surface that limit
loudly (the expression-position error) rather than let it corrupt results silently — the same
"refuse, don't miscompile" stance as §1.

## 16. Constructors, dunders, and inheritance

**The choice.**
- **Constructor.** `__init__` becomes a smart constructor `C.new` — deliberately *not* `C.mk`,
  because `C.mk` is the name Lean auto-generates for the structure's raw field constructor, and we
  don't want to collide with it. A straight-line `__init__` (only `self.x = expr`) emits a record
  literal so unset fields fall back to declared defaults; anything with control flow threads a
  mutable `self` from `default`. No `__init__` → a defaults-only `C.new`.
- **Dunders → typeclass instances.** `__add__`/`__sub__`/`__mul__` become instances of the runtime
  operator classes (`PyHAdd C C C`, …), `__eq__` becomes a `BEq C` instance, `__str__`/`__repr__`
  become a `PyPrintable C` instance. Every *other* method is a plain `def C.method`.
- **Inheritance.** Single inheritance only, via `structure C extends Base`; multiple inheritance is
  a hard error. Inherited fields are pruned from the subclass (Lean rejects redeclaring them), and
  the dispatch tables fold base methods into the subclass.

**Why map dunders to typeclasses rather than plain defs.** Because then `a + b` on two class
instances uses the *same* `+ₚ` notation and the same lowering as `a + b` on ints — the operator
machinery (§18) doesn't need to know whether its operands are builtin or user-defined. A user class
with `__add__` slots straight into the existing operator story. Regular methods have no such
notation to hook, so they stay plain defs. The known cost: a dunder is forced to return the class
type (`__add__ -> float` won't type-check) — a documented gap, not a silent miscompile.

**Why single inheritance only.** Multiple inheritance has no faithful `structure extends` encoding
(MRO, diamond resolution), so rather than approximate it we reject it. Single inheritance maps
cleanly and covers the overwhelming majority of real classes.

## 17. Class dispatch stamping: helping a statement-at-a-time backend

**The problem.** The Lean backend is a persistent server that sees *one statement at a time* with
fresh state per statement (§3). But to lower `obj.method(args)` it needs to know `obj`'s *class* —
information that lives in a `x = C(...)` binding possibly many statements earlier.

**The choice.** The Python side, which sees the whole module, resolves each receiver's class ahead
of time and **stamps the call node** with hints: `_class_ctor: "C"` on `C(...)`,
`_receiver_class: "C"` + `_is_mutator` on `obj.m(...)`, `_static_class` for static/class methods.
The backend reads the stamp and lowers deterministically; a Lean-side class registry is only the
fallback.

**Why stamp in Python rather than track state in the backend.** Threading cross-statement type
state through the backend would break the clean "one statement, fresh state" protocol that makes
the server simple and the per-node error attribution precise (§3). The whole-module knowledge
already exists on the Python side; passing it as a per-node annotation keeps the backend a pure
function of its input. This is, again, the §4 pattern: compute global facts once in Python, carry
them on the node, keep the generator local.

## 18. Custom operators with `outParam` — and the `Rat` default-instance hazard

**The choice.** Arithmetic doesn't use Lean's `+`/`*`; it uses custom notations `+ₚ -ₚ *ₚ /ₚ %ₚ ^ₚ`
backed by classes `PyHAdd`/`PyHMul`/… (`PyAPI/Operators.lean`), each with an **`outParam` result
type**. So `PyHAdd Int Rat Rat`, `PyHAdd Int Int Int`, and so on are all separate instances, and
the result type is *computed* from the operand types.

**Why not reuse Lean's `+`.** Python freely mixes numeric types (`int + float`, `int + Rat`), but
Lean's stock `HAdd` has no heterogeneous `HAdd Nat Int` / `HAdd Rat Int` instances. We need a
family of widening instances Lean's operators simply don't provide, so we define our own class
hierarchy where we can add them.

**Why `outParam` on the result.** So that once the operand types are known, the result type
*reduces to a concrete type* instead of staying an unsolved metavariable. That reduction is what
lets a later `pyGetItem`/`pyIter`/`PyPrintable` on the result resolve its own instance. A stuck
result type would stall everything downstream.

**The `@[default_instance]` hazard (why the tuning is delicate).** Defaulting priorities have to be
set by hand. If the mixed `Rat` instances are marked as defaults, an *unconstrained* operand
(a not-yet-typed parameter) gets pinned to `ℚ` — which then forces the surrounding code (an
integer-only `pyFloorDiv`, or a list's element type) into `ℚ` and fails. So the concrete
`Int + Int = Int` instance is given a *higher* defaulting priority to win the tie, and the `Rat`
mixed instances exist but are deliberately *not* defaults. This is subtle enough that the code
comments flag it in several places; it's a genuine design cost of the heterogeneous-operator
approach, and worth recording so nobody "simplifies" it by marking those instances default.

## 19. One Python name, many meanings — dispatch by instance, not by codegen

**The choice.** `len(x)` emits one Lean call — `pyLen x` — whether `x` is a list, a string, a dict,
or a set. `x[i]`, `x in y`, `sorted(x)`, `reversed(x)`, `x + y` are all the same story: codegen
emits a single stable name (`pyGetItem`, `pyContains`, `pySort`, `pyReversed`, `+ₚ`, …) and Lean's
*instance resolution* selects the actual implementation from the operand's type. The generator never
branches on "is this a list or a string?" — because at the moment it emits the call it usually
*can't* tell (the value may be a bare parameter whose type isn't fixed yet).

**Why let the type system dispatch instead of codegen.** Two payoffs. (1) *Codegen stays simple and
type-blind.* It lowers syntax one node at a time and frequently doesn't know the runtime type of a
subexpression, so "which `len`?" is a decision it's in the wrong position to make. Deferring to
instance resolution — which runs *after* elaboration has worked out types — puts the decision
exactly where the information finally exists. (2) *The system is open.* Making `len` work on a new
container is one new `PyLen` instance in the runtime; the `len` lowering, the IR, and the generator
don't change. The Python surface (`len`, `[]`, `in`, `+`, `sorted`) is a fixed, tiny name→name table
(`Attributes.lean` and the builtin registry); every type-dependent variation lives in the runtime as
instances.

**Why not emit type-specialised names (`pyListLen` vs `pyStringLen`).** Then codegen would have to
*know* the operand's type to choose the name — reintroducing precisely the type inference we were
avoiding, and breaking on `len(param)` where the type isn't yet pinned. It would also turn every new
container into a codegen change rather than a one-line runtime addition. One name plus instances
keeps the "Python syntax → Lean name" mapping fixed and pushes all the variation into instance
resolution.

This is the same mechanism as the operator classes (§18), and it is *why* the protocol types must be
`outParam` (§20, next): only then does the result type reduce to something concrete once the
container type is known, so the value `len` (or `x[i]`) produces can itself be printed, added, or
indexed further.

## 20. Extensible protocols use `outParam`, not associated types

**The choice.** The container protocols (`PyLen`, `PyGetItem`, `PySetItem`, `PyIterable`, …, in
`PyAPI/CommonProtocols/`) carry their varying types (index type, element type) as **`outParam`
class parameters**, never as associated-type *fields* of the class.

**Why.** Same reason as §18's result type: an `outParam` reduces to a concrete type as soon as the
container type is known, so downstream instance resolution (printing the element, adding it,
indexing it again) can proceed. An associated-type projection like `inst.Value` stays "stuck" — it
never reduces to a concrete type on its own — and breaks every instance search that depends on it.
This is a documented, load-bearing convention: new runtime types extend a protocol by *adding an
instance*, not by touching codegen, and the `outParam` shape is what keeps that extension from
poisoning type inference.

## 21. Elaboration-order-driven lowering (comprehensions, subscripts, strings)

A recurring, non-obvious theme: **we choose the emitted syntax so that Lean's elaborator resolves
types in the order that recovers Python's meaning.**

- **Comprehensions** lower to a `pyIter → filter → map` pipeline, and deliberately emit the
  *dot form* `(xs).map (fun x => ...)` rather than the prefix `List.map (fun x => ...) xs`. Why:
  in the dot form the iterable (whose element type is known) elaborates *first* and binds the
  lambda's parameter type; the prefix form would elaborate the lambda first, where the `Rat`
  default (§18) would prematurely pin an unconstrained `x` to `ℚ`. The `map`-vs-`mapM` choice is
  made by the purity predicates of §7. Dict comprehensions build `(k, v)` pairs then `ofList` (later
  keys win, matching Python); set comprehensions dedup via a set.
- **Subscript and slicing** dispatch through protocol typeclasses (`pyGetItem`, `pySlice`) rather
  than committing to a container type in codegen — because the generator often *can't* tell whether
  `a[1:]` is a string or a list (`a` may be a bare parameter). The runtime instance decides, so a
  `String` slices to `String` and a `List` to `List`, all from one emitted call.
- **Strings** are indexed, sliced, and iterated by **codepoint**, via `s.toList : List Char`,
  deliberately diverging from Lean's native byte/`String.Pos` indexing — because Python strings are
  sequences of codepoints and `s[i]` must mean the i-th character, not the i-th byte. There is no
  separate character type: `s[i]` yields a length-1 `String`, since Python has none either, which
  keeps `s[i] == 'x'`, `ord(s[i])`, and string methods all interoperable.

The unifying principle: codegen decides *syntax*, and the syntax is chosen to steer the elaborator,
because the runtime instances (not the generator) hold the type knowledge.

## 22. Proof search: `taste?` / Pastafolio, and splicing the proof back

**The choice.** Pure asserts and specs are discharged by `taste?`, a portfolio tactic built on a
reusable engine (`PyVerify/Pastafolio/`). The engine is deliberately **domain-agnostic**: it
provides the *mechanism* (race a set of candidate tactics), and everything domain-specific lives in
a `Profile` the caller supplies. It splits candidates into **simplifiers** (make progress without
closing — `intro`, `simp_all`, `push_cast`) run to a fixpoint with cycle detection, and **closers**
(must *fully* close — `ring`, `omega`, `linarith`, `nlinarith`, `grind`, `aesop`); a closer that
only normalises without closing is *rejected* so it never lands in the recorded proof as dead
weight. Each candidate runs under an isolated heartbeat budget so one expensive tactic can't drain
the search.

**Why splice the concrete winner back over `taste?`.** Once search finds the tactic that closes a
goal, `py2lean` *replaces* `:= by taste?` in the source with the concrete winning tactic (e.g.
`:= by ring`), matched to the goal by **byte offset**, not append order. Why: the concrete tactic
is faster and stable on re-runs, and — critically — a `taste?` that found nothing becomes a visible
`sorry` with a yellow warning, so a failed proof can never masquerade as a success. Position-based
matching matters because some obligations are self-discharged (an `mvcgen ... with taste?` whose
VCs close themselves record *no* winner); zipping winners to sites by order would then shift every
later proof onto the wrong goal.

**Why `@[taste_ingr]` tagging.** Every proved pure function and assert theorem is tagged into the
`taste_ingr` simp set (and best-effort registered with `grind`), so later proofs get earlier
results as reusable ingredients — leaf-first lemma reuse — without the search having to name each
one. Tagging is best-effort: a lemma with no usable shape is skipped, so a bad pattern never breaks
the build.

## 23. Contracts as library calls, in three tracks

**The choice.** Specifications are written as *calls* to markers from a `passta` library —
`Requires(...)`, `Ensures(...)`, `Invariant(...)`, `Decreases(...)`, `Assert(...)`, `Result()` —
not as magic comments. A function's shape then selects one of three verification tracks: pure
straight-line code → a `taste?`-closed spec theorem; a `for`-loop with an `Invariant` → **Track M**
(emit the body in `Id` so `mvcgen` sees the `do`, prove a Hoare triple); a `while` with
`Invariant` + `Decreases` → **Track W** (the `pyWhile` combinator of §12).

**Why markers-as-calls rather than comments.** A call goes through the real Python parser and the
annotation passes — it has a location, its arguments are real expressions that get type-checked and
translated alongside the code, and `Result()` can stand in for the return value in a postcondition.
A comment is unstructured text the pipeline would have to re-parse by hand and couldn't type-check.
Contracts-as-code means the spec is a first-class part of the program the same machinery already
understands.

## 24. Best-effort by default, with a linter

**The choice.** When the transpiler hits something it can't translate (a foreign library, an
unsupported construct), it emits a `pyUnsupported("<original source>")` placeholder and *keeps
going*, so the rest of the file still compiles. A dedicated linter (`linter.unsupported`, on by
default) flags every placeholder with a yellow warning. `--strict` flips this to fail-hard.

**Why best-effort by default rather than fail-fast.** One unsupported line in a 200-line program
shouldn't cost you the other 199. Degrading locally lets you see how far the translation got, run
and prove the supported parts, and get a precise, linted list of exactly what needs attention —
which is far more useful than a single early abort. `--strict` exists for when you specifically want
a guarantee that *nothing* was degraded (e.g. in the test harness). Crucially, the placeholder is
*loud*, not silent: it prints its original source and raises a warning at every use, so a
degradation can't hide.

## 25. Printing: a Python-flavoured `PyPrintable`

**The choice.** Values are printed through a `PyPrintable` typeclass, kept intentionally separate
from Lean's `ToString`/`Repr` so runtime values render the *Python* way: `True`/`False` (not
`true`/`false`), `None` for unit, Python-style list/tuple/dict brackets, and rationals as decimals
(`1.5`, not `3/2`) to match exact-mode's `float → ℚ`. A low-priority `Repr`-fallback instance means
a new runtime type prints *something* without being forced to define `PyPrintable` on day one.

**Why not just reuse `ToString`/`Repr`.** They render Lean's way, which would make the output look
like Lean, not like the Python program the user wrote. Since matching Python's observable behaviour
is the whole point, printing gets its own typeclass. (In exact/prove mode `print` is a no-op anyway
— §9 — because a `noncomputable ℝ` has no printable form; the arguments are still elaborated so the
line type-checks, then discarded.)

## The shape of it, in one paragraph

We translate the statically-meaningful subset of Python via a deterministic AST walk, because
only a total, auditable function — checked by the Lean elaborator — can be trusted where an LLM
cannot. Python does the parsing and inference it's good at and hands Lean a JSON-lines IR;
Lean does the syntax and type-checking it's good at, over a persistent process so imports are paid
for once. A pre-pass recovers the types Python omitted. Behaviour lives in a runtime, syntax
decisions in a code generator, and libraries are mapping tables between them — and because the
generator stays type-blind, one emitted name like `pyLen` or `+ₚ` means whatever the operand's type
selects, so a new type joins the system by adding an instance, not by editing codegen. Classes
become plain structures and provable functions; control flow becomes native `do` blocks, with
module-level mutation threaded as explicit state. Numbers default to
exact `ℚ` (provable *and* runnable), rising to `ℝ` only for transcendentals and dropping to `Float`
only when you ask to just run. And every function is lowered to the least-powerful monad it can
live in — pure term, then `Id.run do`, then `Except`, then `IO` — because each rung up the ladder
is a rung down in what you can prove, and the whole point was to keep as much of the program
provable as the program will allow.
