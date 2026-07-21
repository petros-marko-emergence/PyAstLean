import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def f := fun (a : PyAny) ↦ !PastaLean.pyTruthy a && PastaLean.pyTruthy a

attribute [simp, taste_ingr] f

def f'rn := fun (a : PyAny) ↦ !PastaLean.pyTruthy a && PastaLean.pyTruthy a