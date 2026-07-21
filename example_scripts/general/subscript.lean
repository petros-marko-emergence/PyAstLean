import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def arr :=
  [(1 : Int), (2 : Int), (3 : Int)]

def result :=
  arr⦋(0 : Int)⦌

def foo :=
  Id.run
    (do
      let mut x : String := "hi"
      let mut y : String := x⦋(0 : Int)⦌
      y := y *ₚ (10 : Int)
      let mut z : String := PastaLean.pySlice y (some (2 : Int)) (some (-(3 : Int))) none
      return z)

attribute [simp, taste_ingr] foo

def foo'rn :=
  Id.run
    (do
      let mut x : String := "hi"
      let mut y : String := x⦋(0 : Int)⦌
      y := y *ₚ (10 : Int)
      let mut z : String := PastaLean.pySlice y (some (2 : Int)) (some (-(3 : Int))) none
      return z)

def bar :=
  let x := "hi"
  let y := PastaLean.pySlice x (some (100 : Int)) (some (-(2000 : Int))) none
  y

attribute [simp, taste_ingr] bar

def bar'rn :=
  let x := "hi"
  let y := PastaLean.pySlice x (some (100 : Int)) (some (-(2000 : Int))) none
  y