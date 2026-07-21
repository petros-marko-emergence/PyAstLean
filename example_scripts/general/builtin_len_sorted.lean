import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def builtin_len_sorted :=
  let xs := [(5 : Int), (1 : Int), (3 : Int)]
  let s := "dbca"
  let d := Std.HashMap.ofList [("z", (9 : Int)), ("a", (1 : Int)), ("m", (4 : Int))]
  let lx := PastaLean.pyLen xs
  let ls := PastaLean.pyLen s
  let ld := PastaLean.pyLen d
  let sx := PastaLean.pySort xs
  let ss := PastaLean.pySort s
  let sd := PastaLean.pySort d
  (lx, (ls, (ld, (sx, (ss, sd)))))

attribute [simp, taste_ingr] builtin_len_sorted

def builtin_len_sorted'rn :=
  let xs := [(5 : Int), (1 : Int), (3 : Int)]
  let s := "dbca"
  let d := Std.HashMap.ofList [("z", (9 : Int)), ("a", (1 : Int)), ("m", (4 : Int))]
  let lx := PastaLean.pyLen xs
  let ls := PastaLean.pyLen s
  let ld := PastaLean.pyLen d
  let sx := PastaLean.pySort xs
  let ss := PastaLean.pySort s
  let sd := PastaLean.pySort d
  (lx, (ls, (ld, (sx, (ss, sd)))))

def in_place_sort :=
  Id.run
    (do
      let mut xs : List Int := [(4 : Int), (1 : Int), (3 : Int), (2 : Int)]
      xs := PastaLean.pySort xs
      return xs)

attribute [simp, taste_ingr] in_place_sort

def in_place_sort'rn :=
  Id.run
    (do
      let mut xs : List Int := [(4 : Int), (1 : Int), (3 : Int), (2 : Int)]
      xs := PastaLean.pySort xs
      return xs)