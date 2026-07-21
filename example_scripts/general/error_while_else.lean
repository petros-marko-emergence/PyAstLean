import PastaLean
import Libraries
import Std.Tactic.Do

open PastaLean
open Libraries
open Std.Do

set_option linter.all false
set_option mvcgen.warning false

set_option maxHeartbeats 0

def fail_while_else :=
  Id.run do
    let mut __py_broke_1 := false
    while (Bool.true) do
      let _ := ()
    if (!__py_broke_1) then 
      let _ := ()
    else
      let _ := ()

attribute [simp, taste_ingr] fail_while_else

def fail_while_else'rn :=
  Id.run do
    let mut __py_broke_1 := false
    while (Bool.true) do
      let _ := ()
    if (!__py_broke_1) then 
      let _ := ()
    else
      let _ := ()