import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- Default parameter values (Python `def f(a, b=10)`) become Lean `optParam` binders
-- (`def f (a) (b := 10)`), so a call with fewer args applies the defaults instead of being a partial
-- application. Covered here: free functions, methods, and constructors — including the `None`-default
-- node pattern (`TreeNode.left`) whose field types must be `Option TreeNode`.
def add (a : Int) (b : Int := (10 : Int)) :=
  a +ₚ b

attribute [simp, taste_ingr] add

def add'rn (a : Int) (b : Int := (10 : Int)) :=
  a +ₚ b

def greet (name : String) (greeting : String := "hi") (times : Int := (2 : Int)) :=
  greeting +ₚ name *ₚ times

attribute [simp, taste_ingr] greet

def greet'rn (name : String) (greeting : String := "hi") (times : Int := (2 : Int)) :=
  greeting +ₚ name *ₚ times

structure Counter where
  value : Int
  step : Int
  deriving Inhabited, Repr, BEq

def Counter.new (start : _ := (0 : Int)) (step : _ := (1 : Int)) : Counter :=
  ({ value := start, step := step } : Counter)

def Counter.bumped (self : Counter) («by» : _ := (1 : Int)) :=
  self.value +ₚ «by» *ₚ self.step

attribute [simp, taste_ingr] Counter.bumped

structure Counter'rn where
  value : Int
  step : Int
  deriving Inhabited, Repr, BEq

def Counter'rn.new (start : _ := (0 : Int)) (step : _ := (1 : Int)) : Counter'rn :=
  ({ value := start, step := step } : Counter'rn)

def Counter'rn.bumped (self : Counter'rn) («by» : _ := (1 : Int)) :=
  self.value +ₚ «by» *ₚ self.step

structure TreeNode where
  val : Int
  left : Option TreeNode
  right : Option TreeNode
  deriving Inhabited, Repr, BEq

def TreeNode.new (val : _ := (0 : Int)) (left : Option TreeNode := Option.none)
    (right : Option TreeNode := Option.none) : TreeNode :=
  ({ val := val, left := left, right := right } : TreeNode)

structure TreeNode'rn where
  val : Int
  left : Option TreeNode'rn
  right : Option TreeNode'rn
  deriving Inhabited, Repr, BEq

def TreeNode'rn.new (val : _ := (0 : Int)) (left : Option TreeNode'rn := Option.none)
    (right : Option TreeNode'rn := Option.none) : TreeNode'rn :=
  ({ val := val, left := left, right := right } : TreeNode'rn)

def main : IO Unit := do
  let inputText ← IO.getStdin >>= fun h => h.readToEnd
  let inputLines := String.splitOn inputText "\n"
  let inputStream : PastaLean.ProofMode.IOStream :=
    ⟨0, fun i => PastaLean.ProofMode.IOResult.success (List.getD inputLines i "")⟩
  let initState : PastaLean.ProofMode.IOState := ⟨inputStream, []⟩
  let (result, finalState) :=
    (((do
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add (5 : Int))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (add (5 : Int) (20 : Int))]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (greet "x")]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (greet "x" "yo" (1 : Int))]
          let mut c := Counter.new
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (Counter.bumped c)]
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (Counter.bumped c (5 : Int))]
          let mut c2 := Counter.new (10 : Int) (2 : Int)
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg (Counter.bumped c2 (3 : Int))]
          let mut leaf := TreeNode.new (2 : Int)
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg leaf.val]
          let mut root := TreeNode.new (1 : Int) leaf
          let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg root.val]
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
  let _ ← pyPrintIO [pyPrintArg (add'rn (5 : Int))]
  let _ ← pyPrintIO [pyPrintArg (add'rn (5 : Int) (20 : Int))]
  let _ ← pyPrintIO [pyPrintArg (greet'rn "x")]
  let _ ← pyPrintIO [pyPrintArg (greet'rn "x" "yo" (1 : Int))]
  let mut c := Counter'rn.new
  let _ ← pyPrintIO [pyPrintArg (Counter'rn.bumped c)]
  let _ ← pyPrintIO [pyPrintArg (Counter'rn.bumped c (5 : Int))]
  let mut c2 := Counter'rn.new (10 : Int) (2 : Int)
  let _ ← pyPrintIO [pyPrintArg (Counter'rn.bumped c2 (3 : Int))]
  let mut leaf := TreeNode'rn.new (2 : Int)
  let _ ← pyPrintIO [pyPrintArg leaf.val]
  let mut root := TreeNode'rn.new (1 : Int) leaf
  let _ ← pyPrintIO [pyPrintArg root.val]
  pure ()