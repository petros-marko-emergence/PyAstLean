import PastaLean.PyAPI.PyAny
import Lean.Elab.Tactic

/-!
# `pyany_cases` — split a `PyAny` goal into one goal per relevant runtime type

A boxed `PyAny` arithmetic operator (`+ₚ`, `-ₚ`, `*ₚ`) dispatches on the runtime constructor, so a
property of boxed values cannot be proved directly — `PyAny` is not a ring. Instead we case on the
constructors of every `PyAny` value in the goal:

* tag-mismatch / unsupported leaves (`int + str`, `none + _`, …) fold to `.none` on *both* sides and
  close by `rfl`;
* the **relevant** leaves — the ones the operators actually support (the numeric tower `int/bool/float`
  with promotion, plus `str` and `list`) — survive, each reduced to its underlying operation
  (`Int`/`Rat` arithmetic, `String.append`, `List.append`).

So the tactic leaves exactly the goals worth proving, and *only* the types the operators support — a
mismatch never becomes a goal. Finish each with the base type's automation, e.g.

```
example (a b : PyAny) : (a +ₚ b) +ₚ b = a +ₚ (b +ₚ b) := by
  pyany_cases a b <;>
    first | rfl | (push_cast; ring) | simp [String.append_assoc, List.append_assoc]
```

`(push_cast; ring)` closes the numeric leaves (`push_cast` reconciles the `Int → Rat` promotion in
the mixed `int/float` cases); `simp [..._assoc]` closes `str`/`list`. `pyany_cases` with no arguments
splits every `PyAny` value in the local context. (The closers live in Mathlib — `import Mathlib.Tactic`.)
-/

namespace PastaLean.PyAny

-- Bridge the operator notation to the raw dispatch functions so the tactic's `simp only` can unfold
-- it. Kept un-`@[simp]` on purpose: only `pyany_cases` should rewrite `+ₚ` into `PyAny.add`, so other
-- proofs (and `taste?`) are unaffected.
theorem hAdd_unfold (a b : PyAny) : a +ₚ b = PyAny.add a b := rfl
theorem hSub_unfold (a b : PyAny) : a -ₚ b = PyAny.sub a b := rfl
theorem hMul_unfold (a b : PyAny) : a *ₚ b = PyAny.mul a b := rfl

open Lean Elab Tactic Meta

/-- The non-internal local hypotheses whose type is exactly `PyAny`. -/
private def pyAnyLocalNames : TacticM (Array Ident) := do
  let mut ids := #[]
  for decl in (← getLCtx) do
    if decl.isImplementationDetail then continue
    if decl.type.isConstOf ``PastaLean.PyAny then
      ids := ids.push (mkIdent decl.userName)
  return ids

/-- `pyany_cases x y …` — case-split the named `PyAny` values (or every `PyAny` value in context if
none are named), discharge the tag-mismatch leaves, and reduce each surviving leaf to its base type. -/
elab "pyany_cases" ids:(ppSpace colGt ident)* : tactic => do
  let targets ← if ids.isEmpty then pyAnyLocalNames else pure ids
  -- `rcases` (rather than `cases`) so each constructor's field *reuses the original variable name*:
  -- in the `int` leaf the hypothesis is `a : ℤ`, in the `float` leaf `a : ℚ`, etc. — so the context
  -- reads which value became which type (the `none` leaf, with no field, just drops it).
  for id in targets do
    evalTactic (← `(tactic|
      all_goals rcases $id:ident with $id:ident | $id:ident | $id:ident | $id:ident | $id:ident | _))
  evalTactic (← `(tactic|
    all_goals try simp [hAdd_unfold, hSub_unfold, hMul_unfold,
      PyAny.add, PyAny.sub, PyAny.mul, PyAny.numBinop, PyAny.asNum, Option.getD,
      PyAny.int.injEq, PyAny.bool.injEq, PyAny.str.injEq, PyAny.float.injEq, PyAny.list.injEq]))

end PastaLean.PyAny
