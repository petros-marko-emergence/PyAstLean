import Lean
open Lean

def hello := "world"

namespace PyAstLean

/-- Minimal runtime value for translated Python exceptions. -/
structure PyException where
  kind : String
  msg : String
  deriving Inhabited, Repr, BEq

/-- Concrete exception monad used for translated Python code that can raise. -/
abbrev PyExcept (α : Type) := Except PyException α

instance : ToString PyException where
  toString exc :=
    if exc.msg.isEmpty then
      exc.kind
    else
      s!"{exc.kind}: {exc.msg}"

def pyPrint {α : Type} [ToString α] (_ : α) : Unit := ()

end PyAstLean
