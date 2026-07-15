import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def main' : IO Unit := do
  let _ := pyUnsupported "unsupported FunctionDef (backend could not translate)"
  pure ()

def main''rn : IO Unit := do
  let _ := pyUnsupported "unsupported FunctionDef (backend could not translate)"
  pure ()

noncomputable def main : IO Unit := do
  let _ := _root_.main'
  pure ()

def main'rn : IO Unit := do
  let _ := _root_.main''rn
  pure ()
