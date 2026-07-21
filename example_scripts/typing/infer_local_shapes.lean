import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- A captured local's type is read off its literal shape (TypeInfer.ofValue), so the lifted helper
-- gets a typed parameter Lean can resolve; an unannotated class field is typed the same way.
structure Counter where
  c : List Int
  tag : String
  deriving Inhabited, Repr, BEq

def Counter.new : Int → Counter := fun (n : Int) ↦ ({ c := PastaLean.pyListRepeat [(0 : Int)] n, tag := "x" } : Counter)

structure Counter'rn where
  c : List Int
  tag : String
  deriving Inhabited, Repr, BEq

def Counter'rn.new : Int → Counter'rn := fun (n : Int) ↦
  ({ c := PastaLean.pyListRepeat [(0 : Int)] n, tag := "x" } : Counter'rn)

private partial def _solve_go : Int → Int → List Int → Int := fun (i : Int) ↦ fun (n : Int) ↦ fun (grid : List Int) ↦
  if decide (i ≥ n) then (0 : Int) else grid⦋i⦌ +ₚ _solve_go (i +ₚ (1 : Int)) n grid

def solve := fun (n : Int) ↦
  let grid := PastaLean.pyListRepeat [(0 : Int)] n
  _solve_go (0 : Int) n grid

attribute [simp, taste_ingr] solve

private partial def _solve_go'rn : Int → Int → List Int → Int := fun (i : Int) ↦ fun (n : Int) ↦
  fun (grid : List Int) ↦ if decide (i ≥ n) then (0 : Int) else grid⦋i⦌ +ₚ _solve_go'rn (i +ₚ (1 : Int)) n grid

def solve'rn := fun (n : Int) ↦
  let grid := PastaLean.pyListRepeat [(0 : Int)] n
  _solve_go'rn (0 : Int) n grid

def main' :=
  ((do
      let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (solve (3 : Int))]) :
    PastaLean.ProofMode.PyProofM _)

attribute [simp] main'

def main''rn :=
  ((do
      let _ ← pyPrintIO [pyPrintArg (solve'rn (3 : Int))]) :
    IO _)

def main : IO Unit := do
  let _ := main'
  pure ()

def main'rn : IO Unit := do
  let _ := main''rn
  pure ()