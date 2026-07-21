import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def sum_to_n := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange (n +ₚ (1 : Int)) (1 : Int))do
        total := total +ₚ i
      return total)

attribute [simp, taste_ingr] sum_to_n

def sum_to_n'rn := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange (n +ₚ (1 : Int)) (1 : Int))do
        total := total +ₚ i
      return total)