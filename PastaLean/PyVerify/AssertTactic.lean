import Mathlib
import PastaLean.PyAPI.Operators

open Lean Elab Tactic Meta Meta.Tactic.TryThis Term

-- The `taste_ingr` simp set is registered in `PastaLean.PyAPI.Operators` (imported above) so the
-- operator rewrite lemmas can join it; the code generator also tags every pure prove-version
-- function with it. `taste?` unfolds the whole set with `simp [taste_ingr]`.

namespace PastaLean

/-!
# `taste` — search for a proof of a transpiled `assert`, or fall back to `sorry`

Generated `assert` statements emit `… := by taste`. When elaborated, this tactic tries a
fixed list of candidate tactics in order; the first one that *closes the goal* is kept, else it fails.
-/


/-- The candidate tactics tried for an assert goal, in order. Edit this list to taste. -/
def assertCandidates : TacticM (Array (TSyntax `tactic)) := do
  return #[
    ← `(tactic| (intros <;> simp only [taste_ingr] <;> push_cast <;> ring)),
    ← `(tactic| (intros <;> simp (config := { zetaDelta := true }) only [taste_ingr] <;> push_cast <;> ring)),
    ← `(tactic| (intros <;> simp only [taste_ingr] at * <;> push_cast at * <;> nlinarith)),
    ← `(tactic| (intros <;> simp (config := { zetaDelta := true }) only [taste_ingr] at * <;> push_cast at * <;> nlinarith)),
    -- General fallbacks.
    ← `(tactic| simp_all [taste_ingr]),
    ← `(tactic| grind +locals +suggestions),
    ← `(tactic| try?),
  ]

syntax (name := assertProveStx) "taste?" : tactic

/--
Check if the tactics works or not
-/
def checkTactic (target : Expr) (tac : Syntax) : TermElabM (Option Nat) :=
  withoutModifyingState do
    try
      let goal ← mkFreshExprMVar target
      let (goals, _) ← withoutErrToSorry do
        Lean.Elab.runTactic goal.mvarId! tac
      return some goals.length
    catch _ =>
      return none

@[tactic assertProveStx]
def evalAssertProve : Tactic := fun stx => do
  let candidates ← assertCandidates
  let target ← getMainTarget
  let sry ← `(tactic| sorry)
  for tac in candidates do
    let res ← checkTactic target tac
    match res with
    | some k =>
        addSuggestion stx tac (origSpan? := stx) -- "Try this: <tac>"
        evalTactic tac
        return
    | none =>
      addSuggestion stx sry (origSpan? := stx)
      evalTactic sry

end PastaLean
