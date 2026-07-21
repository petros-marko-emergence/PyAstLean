import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def builtin_functional :=
  let xs := [(1 : Int), (2 : Int), (3 : Int), (4 : Int)]
  let ys := [(10 : Int), (20 : Int), (30 : Int)]
  let letters := "cab"
  let mapped := PastaLean.pyMap (fun x ↦ x +ₚ (1 : Int)) xs
  let filtered := PastaLean.pyFilter (fun x ↦ x %ₚ (2 : Int) == (0 : Int)) xs
  let zipped := PastaLean.pyZip xs ys
  let enumerated := PastaLean.pyEnumerate letters
  let total := PastaLean.pySum xs
  let smallest := PastaLean.pyMin xs
  let largest := PastaLean.pyMax xs
  let reduced := Libraries.functools.pyReduce xs (fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x) (some (0 : Int))
  (mapped, (filtered, (zipped, (enumerated, (total, (smallest, (largest, reduced)))))))

attribute [simp, taste_ingr] builtin_functional

def builtin_functional'rn :=
  let xs := [(1 : Int), (2 : Int), (3 : Int), (4 : Int)]
  let ys := [(10 : Int), (20 : Int), (30 : Int)]
  let letters := "cab"
  let mapped := PastaLean.pyMap (fun x ↦ x +ₚ (1 : Int)) xs
  let filtered := PastaLean.pyFilter (fun x ↦ x %ₚ (2 : Int) == (0 : Int)) xs
  let zipped := PastaLean.pyZip xs ys
  let enumerated := PastaLean.pyEnumerate letters
  let total := PastaLean.pySum xs
  let smallest := PastaLean.pyMin xs
  let largest := PastaLean.pyMax xs
  let reduced := Libraries.functools.pyReduce xs (fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x) (some (0 : Int))
  (mapped, (filtered, (zipped, (enumerated, (total, (smallest, (largest, reduced)))))))

def functools_reduced :=
  let xs := [(1 : Int), (2 : Int), (3 : Int)]
  Libraries.functools.pyReduce xs (fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x) (some (0 : Int))

attribute [simp, taste_ingr] functools_reduced

def functools_reduced'rn :=
  let xs := [(1 : Int), (2 : Int), (3 : Int)]
  Libraries.functools.pyReduce xs (fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x) (some (0 : Int))

def reduce_no_init_literal :=
  Libraries.functools.pyReduce [(1 : Int), (2 : Int), (3 : Int)] fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x

attribute [simp, taste_ingr] reduce_no_init_literal

def reduce_no_init_literal'rn :=
  Libraries.functools.pyReduce [(1 : Int), (2 : Int), (3 : Int)] fun (acc : Int) ↦ fun (x : Int) ↦ acc +ₚ x