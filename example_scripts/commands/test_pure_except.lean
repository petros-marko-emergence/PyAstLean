import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

-- !/usr/bin/env python3
/-
Test that pure exceptions (no IO) use PyExceptId in prove mode.
-/
-- CHECK: def validate : Int → PyExceptId Int
def validate : Int → PastaLean.ProofMode.PyProofM Int := fun (x : Int) ↦ do
  if h_1 : x < (0 : Int) then 
    throw (PastaLean.PyException.Raise "ValueError" (ToString.toString "negative"))
  else
    let _ := ()
  let __py_ret_1 := x *ₚ (2 : Int)
  return __py_ret_1

attribute [simp] validate

def validate'rn : Int → PastaLean.PyExcept Int := fun (x : Int) ↦ do
  if h_1 : x < (0 : Int) then 
    throw (PastaLean.PyException.Raise "ValueError" (ToString.toString "negative"))
  else
    let _ := ()
  let __py_ret_1 := x *ₚ (2 : Int)
  return __py_ret_1

-- CHECK: def validate_with_print : Int → PyExceptId Int
def validate_with_print : Int → PastaLean.ProofMode.PyProofM Int := fun (x : Int) ↦ do
  let _ ← PastaLean.ProofMode.pyPrintProof [pyPrintArg x]
  if h_1 : x < (0 : Int) then 
    throw (PastaLean.PyException.Raise "ValueError" (ToString.toString "negative"))
  else
    let _ := ()
  let __py_ret_1 := x *ₚ (2 : Int)
  return __py_ret_1

attribute [simp] validate_with_print

def validate_with_print'rn : Int → PastaLean.PyExcept Int := fun (x : Int) ↦ do
  let _ ← pyPrintIO [pyPrintArg x]
  if h_1 : x < (0 : Int) then 
    throw (PastaLean.PyException.Raise "ValueError" (ToString.toString "negative"))
  else
    let _ := ()
  let __py_ret_1 := x *ₚ (2 : Int)
  return __py_ret_1