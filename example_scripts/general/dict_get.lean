import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def dict_get_variants :=
  let d := Std.HashMap.ofList [("apple", (10 : Int)), ("banana", (20 : Int))]
  let found := PastaLean.pyGetOpt? d "apple"
  let missing := PastaLean.pyGetOpt? d "pear"
  let fallback := PastaLean.pyGetD d "pear" (999 : Int)
  (found, (missing, fallback))

attribute [simp, taste_ingr] dict_get_variants

def dict_get_variants'rn :=
  let d := Std.HashMap.ofList [("apple", (10 : Int)), ("banana", (20 : Int))]
  let found := PastaLean.pyGetOpt? d "apple"
  let missing := PastaLean.pyGetOpt? d "pear"
  let fallback := PastaLean.pyGetD d "pear" (999 : Int)
  (found, (missing, fallback))

def dict_get_len_mix :=
  let d := Std.HashMap.ofList [("x", (7 : Int)), ("y", (9 : Int))]
  let got := PastaLean.pyGetD d "x" (0 : Int)
  let size := PastaLean.pyLen d
  (got, size)

attribute [simp, taste_ingr] dict_get_len_mix

def dict_get_len_mix'rn :=
  let d := Std.HashMap.ofList [("x", (7 : Int)), ("y", (9 : Int))]
  let got := PastaLean.pyGetD d "x" (0 : Int)
  let size := PastaLean.pyLen d
  (got, size)