import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- One `add` definition, called at int and str in the same program: the params are used at genuinely
-- different types (`.any`), so they box to PyAny and dispatch on the runtime tag. Runs off a single
-- definition -> prints 7 then xy.
def add := fun (a : PyAny) ↦ fun (b : PyAny) ↦ a +ₚ b

attribute [simp, taste_ingr] add

def add'rn := fun (a : PyAny) ↦ fun (b : PyAny) ↦ a +ₚ b

def main : IO Unit := do
  let inputText ← IO.getStdin >>= fun h => h.readToEnd
  let inputLines := String.splitOn inputText "\n"
  let inputStream : PastaLean.ProofMode.IOStream :=
    ⟨0, fun i => PastaLean.ProofMode.IOResult.success (List.getD inputLines i "")⟩
  let initState : PastaLean.ProofMode.IOState := ⟨inputStream, []⟩
  let (result, finalState) :=
    (((do
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add (3 : Int) (4 : Int))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add "x" "y")]
          pure ()) :
        PastaLean.ProofMode.PyProofM Unit))
      initState
  let outputLines := finalState.output
  for line in outputLines do
    IO.print line
  match result with
  | .ok _ =>
    pure ()
  | .error err =>
    throw (IO.userError (toString err))

def main'rn : IO Unit := do
  let _ ← pyPrintIO [pyPrintArg (add'rn (3 : Int) (4 : Int))]
  let _ ← pyPrintIO [pyPrintArg (add'rn "x" "y")]
  pure ()