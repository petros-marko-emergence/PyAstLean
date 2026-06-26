import Mathlib
import PastaLean.PyAPI.Core
import PastaLean.PyAPI.TasteIngr

/-!
# Helper lemmas for contract verification

`pyRange n` (Python `range(n)`) is `[0, 1, …, n-1]` as `Int`. mvcgen verifies loops over native
`List.range` out of the box (it recovers "element = index", membership, length, …), but `pyRange`
hides that behind an `Int`-cast. The fix is **one reduction spec** — `pyRange_forIn` — that rewrites
a `pyRange` loop into the equivalent native `List.range` loop (with the cast pushed into the body).
Pass it to mvcgen (`mvcgen [fn, pyRange_forIn] …`) and *every* `pyRange` loop inherits `List.range`'s
full native support, for any invariant style. This is the extensible approach: one spec per Python
container reducing it to its Mathlib primitive, rather than ad-hoc per-invariant lemmas.
-/

namespace PastaLean

/-- The `List Nat → List Int` coercion is elementwise `Int.ofNat`. -/
theorem coe_list_eq (l : List Nat) : (↑l : List Int) = l.map Int.ofNat := by
  induction l with
  | nil => rfl
  | cons h t ih => simp_all [Int.ofNat_eq_natCast]

/-- `pyRange n` (default start 0, step 1) is `List.range n.toNat` cast to `Int`. -/
theorem pyRange_eq_ofNat (n : Int) : pyRange n = (List.range n.toNat).map Int.ofNat := by
  unfold pyRange
  simp only [gt_iff_lt, List.range_eq_range', show (Int.toNat 1) = 1 from rfl, Int.ediv_one,
    Int.emod_one, Int.add_zero, Int.sub_zero, if_pos (show (0 : Int) < 1 by norm_num)]
  rw [← coe_list_eq]; simp

/-- **The reduction spec.** A `pyRange n` loop equals the native `List.range n.toNat` loop with the
`Int` cast pushed into the body. Pass to mvcgen so index-style invariants close as they do for
`List.range`. -/
@[taste_ingr] theorem pyRange_forIn {β : Type} {m : Type → Type} [Monad m] [LawfulMonad m]
    (n : Int) (init : β) (f : Int → β → m (ForInStep β)) :
    forIn (pyRange n) init f = forIn (List.range n.toNat) init (fun (k : Nat) => f (Int.ofNat k)) := by
  rw [pyRange_eq_ofNat, List.forIn_map]

end PastaLean
