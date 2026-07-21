import Mathlib
import PastaLean.PyAPI.CommonProtocols.Bool
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace PastaLean

/-
This file defines the `PyStdAny` protocol, which is for python's `any` function. The output of this function is simply False if all elements are 0, empty, or None, and True otherwise.
-/

class PyStdAny (α : Type) where
  pyStdAny : α → Bool

def pyStdAny {α : Type} [PyStdAny α] (x : α) : Bool :=
  PyStdAny.pyStdAny x

instance {α β : Type} [PyIterable α β] [PyBool β] : PyStdAny α where
  pyStdAny x :=
    (pyIter x).any pyBool

/-
The `PyAll` protocol is Python's `all` function: `True` iff every element is truthy
(an empty iterable is `True`).
-/

class PyAll (α : Type) where
  pyAll : α → Bool

def pyAll {α : Type} [PyAll α] (x : α) : Bool :=
  PyAll.pyAll x

instance {α β : Type} [PyIterable α β] [PyBool β] : PyAll α where
  pyAll x :=
    (pyIter x).all pyBool
