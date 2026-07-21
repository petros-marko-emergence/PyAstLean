import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def nested_loops := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        for j in (PastaLean.pyRange i)do
          total := total +ₚ j
      return total)

attribute [simp, taste_ingr] nested_loops

def nested_loops'rn := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        for j in (PastaLean.pyRange i)do
          total := total +ₚ j
      return total)

def super_nested_loops := fun n ↦
  Id.run
    (do
      let mut res : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        for j in (PastaLean.pyRange n)do
          for k in (PastaLean.pyRange n)do
            for l in (PastaLean.pyRange n)do
              res := res +ₚ (i +ₚ j +ₚ k +ₚ l)
      return res)

attribute [simp, taste_ingr] super_nested_loops

def super_nested_loops'rn := fun n ↦
  Id.run
    (do
      let mut res : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        for j in (PastaLean.pyRange n)do
          for k in (PastaLean.pyRange n)do
            for l in (PastaLean.pyRange n)do
              res := res +ₚ (i +ₚ j +ₚ k +ₚ l)
      return res)

def while_in_for := fun n ↦
  Id.run
    (do
      let mut count : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        let mut j : Int := i
        while (j > (0 : Int)) do
          count := count +ₚ (1 : Int)
          j := j -ₚ (1 : Int)
      return count)

attribute [simp, taste_ingr] while_in_for

def while_in_for'rn := fun n ↦
  Id.run
    (do
      let mut count : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        let mut j : Int := i
        while (j > (0 : Int)) do
          count := count +ₚ (1 : Int)
          j := j -ₚ (1 : Int)
      return count)

def breakable_loop := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        if h_1 : i = (5 : Int) then 
          break
        else
          let _ := ()
        total := total +ₚ i
      let mut j : Int := (0 : Int)
      while (j < n) do
        if h_1 : j ≤ (3 : Int) then 
          continue
        else
          let _ := ()
        total := total +ₚ j
        j := j +ₚ (1 : Int)
      return total)

attribute [simp, taste_ingr] breakable_loop

def breakable_loop'rn := fun n ↦
  Id.run
    (do
      let mut total : Int := (0 : Int)
      for i in (PastaLean.pyRange n)do
        if h_1 : i == (5 : Int) then 
          break
        else
          let _ := ()
        total := total +ₚ i
      let mut j : Int := (0 : Int)
      while (j < n) do
        if h_1 : j ≤ (3 : Int) then 
          continue
        else
          let _ := ()
        total := total +ₚ j
        j := j +ₚ (1 : Int)
      return total)