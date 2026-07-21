import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def func := fun (a : PyAny) ↦ fun (b : PyAny) ↦ fun (c : PyAny) ↦
  PastaLean.pyTruthy a && PastaLean.pyTruthy b && PastaLean.pyTruthy c || PastaLean.pyTruthy a && PastaLean.pyTruthy b

attribute [simp, taste_ingr] func

def func'rn := fun (a : PyAny) ↦ fun (b : PyAny) ↦ fun (c : PyAny) ↦
  PastaLean.pyTruthy a && PastaLean.pyTruthy b && PastaLean.pyTruthy c || PastaLean.pyTruthy a && PastaLean.pyTruthy b