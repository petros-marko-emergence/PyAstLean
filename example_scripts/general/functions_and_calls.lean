import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def add := fun a ↦ fun (b : Int) ↦ a +ₚ b

attribute [simp, taste_ingr] add

def add'rn := fun a ↦ fun (b : Int) ↦ a +ₚ b

def call_add := fun n ↦ add n (1 : Int)

attribute [simp, taste_ingr] call_add

def call_add'rn := fun n ↦ add'rn n (1 : Int)

def keyword_call := fun n ↦ ((add) (a := n)) (b := (2 : Int))

attribute [simp, taste_ingr] keyword_call

def keyword_call'rn := fun n ↦ ((add'rn) (a := n)) (b := (2 : Int))

def many_args := fun a ↦ fun b ↦ fun c ↦ fun d ↦ fun e ↦ a +ₚ b +ₚ c +ₚ d +ₚ e

attribute [simp, taste_ingr] many_args

def many_args'rn := fun a ↦ fun b ↦ fun c ↦ fun d ↦ fun e ↦ a +ₚ b +ₚ c +ₚ d +ₚ e

def complex_func := fun x ↦ fun y ↦ fun z ↦
  Id.run
    (do
      let mut res := x *ₚ y
      res := res +ₚ z
      return res)

attribute [simp, taste_ingr] complex_func

def complex_func'rn := fun x ↦ fun y ↦ fun z ↦
  Id.run
    (do
      let mut res := x *ₚ y
      res := res +ₚ z
      return res)