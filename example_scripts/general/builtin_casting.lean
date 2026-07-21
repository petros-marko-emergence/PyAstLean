import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def builtin_casting :=
  let a := PastaLean.pyInt "42"
  let b := PastaLean.pyStr [(1 : Int), (2 : Int), (3 : Int)]
  let c := PastaLean.pyList "abc"
  let d := PastaLean.pyStr Bool.true
  let e := PastaLean.pyList ((1 : Int), (2 : Int))
  (a, (b, (c, (d, e))))

attribute [simp, taste_ingr] builtin_casting

def builtin_casting'rn :=
  let a := PastaLean.pyInt "42"
  let b := PastaLean.pyStr [(1 : Int), (2 : Int), (3 : Int)]
  let c := PastaLean.pyList "abc"
  let d := PastaLean.pyStr Bool.true
  let e := PastaLean.pyList ((1 : Int), (2 : Int))
  (a, (b, (c, (d, e))))