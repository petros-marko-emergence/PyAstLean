# Proving contract loop invariants — findings & codegen improvements

Experiments on `sum_upto` (`s = 0+1+…+(n-1)`, asserting `s = n(n-1)/2`). Worked examples in
`example_scripts/mvcgen_eg/yours/try.lean` (`sum_upto_spec`, `sum_upto_lr_spec`).

## Two robust invariant styles

| style | invariant | iterates | proves | needs |
|---|---|---|---|---|
| **accumulator** | `s = cur.prefix.sum` | `pyRange` ✓ or `List.range` | loop maintenance (post `True`) | nothing |
| **index** | `2·s = i·(i-1)` (`i := prefix.length`) | **`List.range` only** | **full closed-form Ensures** | native `List.range` |

- **Accumulator** invariants maintain *without* "element = index", so they close over the generated
  `pyRange` def as-is. But with post `True` they only certify the loop is internally consistent —
  to also get the closed-form `Ensures` you need a domain lemma (e.g. Gauss `(pyRange n).sum = n(n-1)/2`),
  which is example-specific and not automatable.
- **Index** invariants reference `i = prefix.length`; at loop exit `prefix.length = n`, so the
  invariant *becomes* the `Ensures` — full functional correctness, **no domain lemma**. But they need
  "element = index", which mvcgen has for `List.range` and **loses for `pyRange`**.

## The essential finding

`range(n)` lowers to **`pyRange n`**, whose elements are `Int`-casts of a `List.range`
(`[↑0, ↑1, …]`). That cast turns the list into a `flatMap`/coercion form that hides "element = index"
from mvcgen + grind. Native `List.range` (Nat) keeps it. Confirmed:

- `pyRange` + index invariant → **fails** (`sorry`).
- `List.range` + index invariant → **proves** the full Ensures.
- `List.range` + division in the invariant (`s = i*(i-1)/2`) → also proves (division-free is nice-to-have, not essential).

## Codegen improvements (in priority order)

1. **Lower verification `range(...)` loops to native `List.range` (the big one).**
   In the Track-M `for`-loop lowering, for the *exact/verification* def emit
   `for i in List.range n.toNat do … (↑i) …` instead of `for i in pyRange n do … i …`
   (cast the loop variable to `Int` at its use sites in the body). The runnable `'rn` twin keeps
   `pyRange`. This single change makes index-style invariants close → full functional correctness
   with **no domain lemmas**. Scope first to the common `range(stop)` shape (start 0, step 1).

2. **Emit invariants division-free.** When scraping `Invariant(s == a // b)`, multiply through to
   `b * s == a`. Avoids integer-division reasoning in `nlinarith`/`grind`. Secondary — `taste?`
   handled the division over `List.range` — but cheaper and more robust.

3. **Pick the invariant style by what the user wrote.** An index-referencing `Invariant`
   (mentions the loop variable) directly yields the closed-form `Ensures` → use path (1). A
   pure-accumulator `Invariant` works on `pyRange` already but its `Ensures` needs a domain lemma.

4. **Keep the `HelperLemmas` (`pyRange_eq`, `pyRange_split`)** as a fallback for `pyRange`-form goals
   and manual proofs, but note they don't auto-apply (grind can't e-match the lambda premise) — which
   is exactly why path (1) is preferred over more lemmas.

## Status

`example_scripts/mvcgen_eg/yours/try.lean` now has both proving with **0 sorry**:
`sum_upto_spec` (accumulator, on the real `pyRange` def) and `sum_upto_lr_spec` (index, `List.range`,
full functional correctness).
