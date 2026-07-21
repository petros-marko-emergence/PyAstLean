import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def count_to := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      while (total < n) do
        total := total +ₚ (1 : Int)
      return total)

attribute [simp, taste_ingr] count_to

def count_to'rn := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      while (total < n) do
        total := total +ₚ (1 : Int)
      return total)