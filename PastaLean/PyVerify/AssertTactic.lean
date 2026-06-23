import Mathlib
import PastaLean.PyAPI.Operators

open Lean Elab Tactic Meta Meta.Tactic.TryThis Term

namespace PastaLean

/-
Here are some extra attributes to make `taste_ingr` better!
-/
attribute [taste_ingr] mul_nonneg add_nonneg

/-- Winning tactic string per assert (or `"sorry"`), in elaboration order; the backend `proveFile`
pass drains this so Python can splice each over its `taste?`. -/
initialize tasteWinnersRef : IO.Ref (Array String) ← IO.mkRef #[]

def candidateStrings : Array String := #[
  "intros <;> simp_all (config := { zetaDelta := true }) [taste_ingr] <;> (try push_cast at *) <;> grind +locals +suggestions",
  "grind +locals +suggestions",
  "intros <;> simp_all (config := { zetaDelta := true }) [taste_ingr] at * <;> push_cast at * <;> nlinarith",
  "simp_all [taste_ingr]"
]

syntax (name := assertProveStx) "taste?" : tactic

/-- Parse a candidate string into tactic syntax (`none` if it doesn't parse). -/
def parseTactic (s : String) : CoreM (Option Syntax) := do
  match Lean.Parser.runParserCategory (← getEnv) `tactic s with
  | .ok stx => return some stx
  | .error _ => return none

def checkTactic (target : Expr) (tac : Syntax) : TermElabM (Option Nat) :=
  withoutModifyingState do
    try
      withCurrHeartbeats do
        let goal ← mkFreshExprMVar target
        let goals ← withoutErrToSorry do
          Tactic.run goal.mvarId! <|
            Tactic.withoutRecover (Tactic.evalTactic tac) *> Tactic.pruneSolvedGoals
        return some goals.length
    catch _ =>
      return none

/-- First candidate that closes `target`, as its clean string, or `none`. -/
def bestCandidate? (target : Expr) : TermElabM (Option String) := do
  for s in candidateStrings do
    if let some tac ← parseTactic s then
      if (← checkTactic target tac) == some 0 then
        return some s
  return none

/-- Record the winning tactic string (or `"sorry"`) for the splice pass, suggest it, and admit the
goal. The real proof is the spliced string, so we don't re-run it here. -/
@[tactic assertProveStx]
def evalAssertProve : Tactic := fun stx => do
  let target ← getMainTarget
  let winner := (← bestCandidate? target).getD "sorry"
  tasteWinnersRef.modify (·.push winner)
  if let some tac ← parseTactic winner then
    addSuggestion stx (⟨tac⟩ : TSyntax `tactic) (origSpan? := stx)
  withCurrHeartbeats (evalTactic (← `(tactic| sorry)))

end PastaLean
