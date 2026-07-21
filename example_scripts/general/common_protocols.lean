import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def len_protocols :=
  let xs := [(1 : Int), (2 : Int), (3 : Int)]
  let s := "hello"
  let d := Std.HashMap.ofList [("a", (1 : Int))]
  let lx := PastaLean.pyLen xs
  let ls := PastaLean.pyLen s
  let ld := PastaLean.pyLen d
  (lx, (ls, ld))

attribute [simp, taste_ingr] len_protocols

def len_protocols'rn :=
  let xs := [(1 : Int), (2 : Int), (3 : Int)]
  let s := "hello"
  let d := Std.HashMap.ofList [("a", (1 : Int))]
  let lx := PastaLean.pyLen xs
  let ls := PastaLean.pyLen s
  let ld := PastaLean.pyLen d
  (lx, (ls, ld))

def iteration_protocols :=
  let xs := [(4 : Int), (5 : Int), (6 : Int)]
  (PastaLean.pyIter xs).map fun x => x

attribute [simp, taste_ingr] iteration_protocols

def iteration_protocols'rn :=
  let xs := [(4 : Int), (5 : Int), (6 : Int)]
  (PastaLean.pyIter xs).map fun x => x