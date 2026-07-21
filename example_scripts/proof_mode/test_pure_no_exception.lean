import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- Test: Pure computation (no IO, no exceptions)
def add := fun a ↦ fun b ↦ a +ₚ b

attribute [simp, taste_ingr] add

def add'rn := fun a ↦ fun b ↦ a +ₚ b