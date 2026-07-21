import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- Test: Pure exception handling (no IO)
def divide := fun a ↦ fun b ↦
  ((do
      try
        let __py_ret_1 := a /ₚ b
        return __py_ret_1
      catch caught =>
        if Bool.true then 
          return (0 : Int)
        else
          throw caught) :
    PastaLean.ProofMode.PyProofM _)

attribute [simp] divide

def divide'rn := fun a ↦ fun b ↦
  ((do
      try
        let __py_ret_1 := PastaLean.pyFloat a /ₚ b
        return __py_ret_1
      catch caught =>
        if Bool.true then 
          return (0 : Int)
        else
          throw caught) :
    PastaLean.PyExcept _)