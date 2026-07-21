import PastaLean.PyAPI.PyAnyProof
import PastaLean

/-! Proofs over boxed `PyAny` values via `pyany_cases` — the tactic splits a goal into one goal per
*relevant* runtime type (numeric tower + str + list), auto-closing every tag-mismatch leaf. -/

open PastaLean

-- `<;> grind` closes every relevant leaf uniformly; quiet the tidiness linters for that shape.
set_option linter.unusedTactic false
set_option linter.unnecessarySeqFocus false

-- The canonical closer: `push_cast; ring` for the numeric leaves, `simp [..._assoc]` for str/list.
example (a b : PyAny) : (a +ₚ b) +ₚ b = a +ₚ (b +ₚ b) := by
  pyany_cases a b <;> grind

-- `*ₚ` is commutative over every type it supports (numeric, and `str*int = int*str`). Note `+ₚ` is
-- NOT (string/list concatenation), and `pyany_cases` correctly leaves that goal open.
example (a b : PyAny) : a *ₚ b = b *ₚ a := by
  pyany_cases a b <;> ring_nf
  grind

-- No explicit arguments: splits every `PyAny` in context.
example (a b : PyAny) : a -ₚ b -ₚ b = a -ₚ (b +ₚ b) := by
  pyany_cases a b <;> grind

-- Multi-return-type value: `def f(x): return x if x > 0 else "neg"` returns a single `PyAny` that is
-- `int` on one path and `str` on another. `pyany_cases` proves a property across *every* type the one
-- value could dynamically be — the whole point of proving over a boxed (un-inferred) slot.
example (x : PyAny) : (x +ₚ x) +ₚ x = x +ₚ (x +ₚ x) := by
  pyany_cases x <;> grind
