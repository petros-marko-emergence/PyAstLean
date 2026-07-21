import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def basic_types :=
  Id.run do
    let mut a : Int := (1 : Int)
    let mut b := (2.5 : Rat)
    let mut c : String := "hello"
    let mut d : Bool := Bool.true
    let mut e : List Int := [(1 : Int), (2 : Int)]
    let mut f := ((1 : Int), "a")
    let __unpack_value_1 := ((3 : Int), (4.5 : Rat))
    let __unpack_pair_1 := __unpack_value_1
    let mut g := Prod.fst __unpack_pair_1
    let mut h := Prod.snd __unpack_pair_1
    let __unpack_value_2 := ((5 : Int), ("world", Bool.false))
    let __unpack_pair_2 := __unpack_value_2
    let mut m := Prod.fst __unpack_pair_2
    let mut n := Prod.fst (Prod.snd __unpack_pair_2)
    let mut p := Prod.snd (Prod.snd __unpack_pair_2)
    let mut tup1 := ("foo", (42 : Int))
    let mut tup2 := (g, h)

attribute [simp, taste_ingr] basic_types

def basic_types'rn :=
  Id.run do
    let mut a : Int := (1 : Int)
    let mut b := (2.5 : Float)
    let mut c : String := "hello"
    let mut d : Bool := Bool.true
    let mut e : List Int := [(1 : Int), (2 : Int)]
    let mut f := ((1 : Int), "a")
    let __unpack_value_1 := ((3 : Int), (4.5 : Float))
    let __unpack_pair_1 := __unpack_value_1
    let mut g := Prod.fst __unpack_pair_1
    let mut h := Prod.snd __unpack_pair_1
    let __unpack_value_2 := ((5 : Int), ("world", Bool.false))
    let __unpack_pair_2 := __unpack_value_2
    let mut m := Prod.fst __unpack_pair_2
    let mut n := Prod.fst (Prod.snd __unpack_pair_2)
    let mut p := Prod.snd (Prod.snd __unpack_pair_2)
    let mut tup1 := ("foo", (42 : Int))
    let mut tup2 := (g, h)

def fstring :=
  let s1 := "Hello"
  let s2 := "World"
  let s3 := s1 +ₚ ", " +ₚ s2 +ₚ "!"
  s! "This is a string: {s3} and this is a number: {(1 : Int) +ₚ (2 : Int)}"

attribute [simp, taste_ingr] fstring

def fstring'rn :=
  let s1 := "Hello"
  let s2 := "World"
  let s3 := s1 +ₚ ", " +ₚ s2 +ₚ "!"
  s! "This is a string: {s3} and this is a number: {(1 : Int) +ₚ (2 : Int)}"

def annotated_vars :=
  let x := (10 : Int)
  let y := (20 : Int)
  x +ₚ y

attribute [simp, taste_ingr] annotated_vars

def annotated_vars'rn :=
  let x := (10 : Int)
  let y := (20 : Int)
  x +ₚ y