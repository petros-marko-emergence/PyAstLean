import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def string_pipeline :=
  let s := "  Py Ast Lean  "
  let trimmed := PastaLean.pyStringStrip s
  let lowered := PastaLean.pyStringLower trimmed
  let parts := PastaLean.pyStringSplit lowered
  let glued := PastaLean.pyStringJoin "-" parts
  glued

attribute [simp, taste_ingr] string_pipeline

def string_pipeline'rn :=
  let s := "  Py Ast Lean  "
  let trimmed := PastaLean.pyStringStrip s
  let lowered := PastaLean.pyStringLower trimmed
  let parts := PastaLean.pyStringSplit lowered
  let glued := PastaLean.pyStringJoin "-" parts
  glued

def list_pipeline :=
  Id.run
    (do
      let mut xs : List Int := [(3 : Int), (1 : Int)]
      xs := PastaLean.pyAppend xs (2 : Int)
      xs := PastaLean.pySort xs
      let mut count : Int := PastaLean.pyLen xs
      let __py_ret_1 := (xs, count)
      return __py_ret_1)

attribute [simp, taste_ingr] list_pipeline

def list_pipeline'rn :=
  Id.run
    (do
      let mut xs : List Int := [(3 : Int), (1 : Int)]
      xs := PastaLean.pyAppend xs (2 : Int)
      xs := PastaLean.pySort xs
      let mut count : Int := PastaLean.pyLen xs
      let __py_ret_1 := (xs, count)
      return __py_ret_1)