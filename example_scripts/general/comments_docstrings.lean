import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- module comment
/-
module doc
second line
-/
def f := fun x ↦
  -- function comment
  /-
  function doc
  -/
  -- before assign
  let y := x +ₚ (1 : Int)
  -- before return
  y

attribute [simp, taste_ingr] f

def f'rn := fun x ↦
  -- function comment
  /-
  function doc
  -/
  -- before assign
  let y := x +ₚ (1 : Int)
  -- before return
  y