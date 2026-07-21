import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def f := fun n ↦
  let x := n +ₚ (1 : Int)
  let y := x *ₚ (2 : Int)
  let x := y -ₚ (1 : Int)
  x +ₚ y

attribute [simp, taste_ingr] f

def f'rn := fun n ↦
  let x := n +ₚ (1 : Int)
  let y := x *ₚ (2 : Int)
  let x := y -ₚ (1 : Int)
  x +ₚ y