import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 800000

-- Multiple return types and per-variable type mutation, both handled by inference boxing the slot to
-- PyAny (the dynamic fallback) and dispatching operations on the runtime tag.
-- A function whose branches return different types (str vs int) → its result is PyAny.
def classify := fun (n : Int) ↦ (if decide (n > (0 : Int)) then "positive" else (0 : Int) : PastaLean.PyAny)

attribute [simp] classify

def classify'rn := fun (n : Int) ↦ (if decide (n > (0 : Int)) then "positive" else (0 : Int) : PastaLean.PyAny)

-- A parameter/local rebound to a different type mid-function, with operations on each type.
def reassigned :=
  let x := (1 : Int)
  let x := x +ₚ (5 : Int)
  let x := "hi"
  let x := x +ₚ "world"
  let y := (3 : Int)
  let y := x
  x +ₚ y

attribute [simp, taste_ingr] reassigned

def reassigned'rn :=
  let x := (1 : Int)
  let x := x +ₚ (5 : Int)
  let x := "hi"
  let x := x +ₚ "world"
  let y := (3 : Int)
  let y := x
  x +ₚ y

-- One `add` used at both int and str (the flagship polymorphic case).
def add := fun (a : PyAny) ↦ fun (b : PyAny) ↦ a +ₚ b

attribute [simp, taste_ingr] add

def add'rn := fun (a : PyAny) ↦ fun (b : PyAny) ↦ a +ₚ b

@[taste_ingr]
theorem add_thm : ∀ a, ∀ b, a +ₚ b +ₚ b = a +ₚ (b +ₚ b) := by intros; simp_all (config := { zetaDelta := true }) [taste_ingr]; pyany_cases <;> grind +locals

-- A try/except whose branches return different types (int vs str) → the whole function is PyAny,
-- so the `PyExcept _` codomain in Exceptions.lean infers `PyAny` on its own.
def describe : Int → PastaLean.ProofMode.PyProofM PastaLean.PyAny := fun (x : Int) ↦ do
  try
    if h_1 : x < (0 : Int) then 
      throw (PastaLean.PyException.Raise "ValueError" "")
    else
      let _ := ()
    return (x : PastaLean.PyAny)
  catch caught =>
    if (caught).OfKind == "ValueError" then 
      return ("negative" : PastaLean.PyAny)
    else
      throw caught

attribute [simp] describe

def describe'rn : Int → PastaLean.PyExcept PastaLean.PyAny := fun (x : Int) ↦ do
  try
    if h_1 : x < (0 : Int) then 
      throw (PastaLean.PyException.Raise "ValueError" "")
    else
      let _ := ()
    return (x : PastaLean.PyAny)
  catch caught =>
    if (caught).OfKind == "ValueError" then 
      return ("negative" : PastaLean.PyAny)
    else
      throw caught

def main : IO Unit := do
  let inputText ← IO.getStdin >>= fun h => h.readToEnd
  let inputLines := String.splitOn inputText "\n"
  let inputStream : PastaLean.ProofMode.IOStream :=
    ⟨0, fun i => PastaLean.ProofMode.IOResult.success (List.getD inputLines i "")⟩
  let initState : PastaLean.ProofMode.IOState := ⟨inputStream, []⟩
  let (result, finalState) :=
    (((do
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (classify (5 : Int))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (classify (-(3 : Int)))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (reassigned)]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add (3 : Int) (4 : Int))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add "x" "y")]
          let mut d1 := (← describe (5 : Int))
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg d1]
          let mut d2 := (← describe (-(2 : Int)))
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg d2]
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
  let result ←
    (((do
            let _ ← pyPrintIO [pyPrintArg (classify'rn (5 : Int))]
            let _ ← pyPrintIO [pyPrintArg (classify'rn (-(3 : Int)))]
            let _ ← pyPrintIO [pyPrintArg (reassigned'rn)]
            let _ ← pyPrintIO [pyPrintArg (add'rn (3 : Int) (4 : Int))]
            let _ ← pyPrintIO [pyPrintArg (add'rn "x" "y")]
            let mut d1 := (← describe'rn (5 : Int))
            let _ ← pyPrintIO [pyPrintArg d1]
            let mut d2 := (← describe'rn (-(2 : Int)))
            let _ ← pyPrintIO [pyPrintArg d2]
            pure ()) :
          PastaLean.PyExcept Unit)).run
  match result with
  | .ok _ =>
    pure ()
  | .error err =>
    throw (IO.userError (toString err))