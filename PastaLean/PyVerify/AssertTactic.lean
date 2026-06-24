import Mathlib
import PastaLean.PyAPI.Operators

open Lean Elab Tactic Meta Meta.Tactic.TryThis Term

namespace PastaLean

/-
Here are some extra attributes to make `taste_ingr` better!
-/
attribute [taste_ingr] mul_nonneg add_nonneg

initialize tasteWinnersRef : IO.Ref (Array String) ← IO.mkRef #[]

/-- The candidate tactics tried for an assert goal, in order. Edit this list to taste. -/
def assertCandidates : TacticM (Array (TSyntax `tactic)) := do
  return #[
    ← `(tactic| simp_all? [taste_ingr]),
    ← `(tactic| simp_all? (config := { zetaDelta := true }) [taste_ingr]),
    ← `(tactic| grind? +locals +suggestions),
    ← `(tactic| ring),
    ← `(tactic| push_cast at * <;> ring),
    ← `(tactic| positivity),
    ← `(tactic| nlinarith),
    ← `(tactic| try?)
  ]

/-- The popular `fun_induction f <;> grind` candidate, derived from the goal. `fun_induction` needs
the function as an argument, so we scan the goal for a function `f` that actually has a functional-
induction principle (`f.induct`) and synthesize `fun_induction f <;> grind` — the `<;>` runs `grind`
on every case the induction splits out. `none` when the goal mentions no such function. -/
def goalFunInductionTac? : TacticM (Option (TSyntax `tactic)) := do
  let tgt ← instantiateMVars (← getMainTarget)
  let env ← getEnv
  for c in tgt.getUsedConstants do
    if env.contains (c.str "induct") then
      let fid := mkIdent c
      return some (← `(tactic| fun_induction $fid <;> grind +locals +suggestions))
  return none

syntax (name := assertProveStx) "taste?" : tactic

def tacToString (tac : TSyntax `tactic) : TacticM String := do
  return (← Lean.PrettyPrinter.ppTactic tac).pretty.replace "✝" ""

/-- Collapse every run of whitespace to a single space (and trim). Keeps a multi-line resolved
suggestion (`simp only [\n  a, b ]`) on one line so it splices cleanly. -/
def collapseWs (s : String) : String := Id.run do
  let mut out := ""
  let mut needSep := false  -- emitted a word, now inside a whitespace gap
  for c in s.toList do
    if c.isWhitespace then
      if !out.isEmpty then needSep := true
    else
      if needSep then out := out.push ' '
      out := out.push c
      needSep := false
  return out

def goalTargets : TacticM (List Expr) := do
  (← getGoals).mapM fun g => do instantiateMVars (← g.getType)

/-- A committed trace tactic (`simp?`/`grind?`/`try?`) logs its resolved form as a
`Try this: <tac>` info message. Recover the first such suggestion from the messages logged since
`nBefore` messages were present, so the recorded proof is the concrete `simp only [...]` rather
than the `simp?` placeholder. `none` when the candidate logged no suggestion. -/
def firstTryThisSince (nBefore : Nat) : TacticM (Option String) := do
  let msgs := (← getThe Core.State).messages.toList.drop nBefore
  for msg in msgs do
    let s ← msg.data.toString
    match (s.splitOn "Try this:")[1]? with
    | some rest =>
      -- the rendered message is `Try this:\n[apply] <tactic>` — `[apply]` is the apply-widget's
      -- link text, so drop it to recover just the tactic.
      let tac0 := collapseWs rest
      let tac := if tac0.startsWith "[apply] " then String.ofList (tac0.toList.drop 8) else tac0
      unless tac.isEmpty do
        return some tac
    | none => pure ()
  return none

/-- Parse a tactic string back into syntax (`none` if it doesn't parse). -/
def parseTactic? (s : String) : TacticM (Option (TSyntax `tactic)) := do
  match Lean.Parser.runParserCategory (← getEnv) `tactic s with
  | .ok stx => return some ⟨stx⟩
  | .error _ => return none

/-- Run `tac`, returning the resulting goal targets, but only when it made real progress (some
goal's target changed or a goal closed) without leaving a `sorry`-closure. `none` means "did
nothing useful / failed / cheated with sorry". This does *not* restore state — the caller owns
the saved state and decides what to roll back to. -/
def runForProgress (tac : TSyntax `tactic) (before : List Expr) (beforeGoals : List MVarId) :
    TacticM (Option (List Expr)) := do
  try
    withoutRecover (evalTactic tac)
    let after ← goalTargets
    if before == after then
      return none
    let afterGoals ← getGoals
    for g in beforeGoals do
      unless afterGoals.contains g do
        if (← instantiateMVars (mkMVar g)).hasSorry then
          return none
    return some after
  catch _ =>
    return none

/-- Run one candidate on the current goal state. Commit and return the rendered tactic text only
when it makes *real progress* — some goal's target changed (a simplification) or a goal closed;
otherwise restore and return `none`.

When the committed candidate logged a `Try this:` suggestion (a trace tactic like `simp?`/`grind?`,
and not a compound `<;>` tactic where one suggestion wouldn't capture the whole thing), we upgrade
the recorded proof from the `?` placeholder to the concrete suggestion — but only after replaying
the suggestion and confirming it reaches the *same* goal state. The `simp only [...]` a `simp?`
suggests doesn't always reproduce (e.g. it under-approximates `let`-zeta), so an unverified upgrade
could splice a proof that no longer elaborates; when replay disagrees we keep the working `?` form. -/
def tryCandidate (tac : TSyntax `tactic) : TacticM (Option String) := do
  let before ← goalTargets
  let beforeGoals ← getGoals
  let nMsgs := (← getThe Core.State).messages.toList.length
  let saved ← saveState
  match ← runForProgress tac before beforeGoals with
  | none =>
    saved.restore
    return none
  | some after =>
    let render ← tacToString tac
    -- try to upgrade to the resolved suggestion, but only if it parses and replays identically
    if (render.splitOn "<;>").length == 1 then
      if let some resolved ← firstTryThisSince nMsgs then
        if let some resolvedStx ← parseTactic? resolved then
          let afterState ← saveState   -- state produced by the original `tac`
          saved.restore                -- rewind and try the suggestion from scratch
          if (← runForProgress resolvedStx before beforeGoals) == some after then
            return some resolved        -- suggestion reproduces — keep its (committed) state
          afterState.restore            -- suggestion diverged — fall back to the original tactic
    return some render

/-- Sweep the candidate list; the first candidate that makes progress is committed (its rendered/
resolved text appended to `acc`), then we loop back from the top on whatever goals remain. `fuel`
bounds the rewriting so two candidates can never ping-pong the goal forever. -/
partial def tasteLoop (cands : Array (TSyntax `tactic)) (fuel : Nat) (acc : Array String) :
    TacticM (Array String) := do
  if fuel == 0 then return acc
  if (← getGoals).isEmpty then return acc
  for tac in cands do
    match ← tryCandidate tac with
    | some rendered => return (← tasteLoop cands (fuel - 1) (acc.push rendered))
    | none => pure ()
  return acc

@[tactic assertProveStx]
def evalAssertProve : Tactic := fun stx => do
  let base ← assertCandidates
  -- Slot the goal-derived `fun_induction f <;> grind` in right after `simp_all?` (index 1).
  let cands := match (← goalFunInductionTac?) with
    | some t => #[base[0]!] ++ #[t] ++ base[1:].toArray
    | none => base
  let used ← tasteLoop cands (cands.size * 4 + 4) #[]
  let numGoals := (← getGoals).length
  if numGoals == 0 then
    -- The concrete proof = the committed candidates, sequenced. Record it for the splice and offer
    -- it in the editor as "Try this", so `taste?` can be replaced by the real proof.
    let proof :=
      if used.size == 1 then used[0]!
      else "(" ++ String.intercalate "; " used.toList ++ ")"
    tasteWinnersRef.modify (·.push proof)
    match Lean.Parser.runParserCategory (← getEnv) `tactic proof with
    | .ok s => addSuggestion stx (⟨s⟩ : TSyntax `tactic) (origSpan? := stx)
    | .error _ => pure ()
  else
    tasteWinnersRef.modify (·.push "sorry")
    evalTactic (← `(tactic| all_goals sorry))

end PastaLean
