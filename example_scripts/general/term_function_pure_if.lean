import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def choose := fun x ↦ if decide (x > (0 : Int)) then (1 : Int) else (2 : Int)

attribute [simp, taste_ingr] choose

def choose'rn := fun x ↦ if decide (x > (0 : Int)) then (1 : Int) else (2 : Int)