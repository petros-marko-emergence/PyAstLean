import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

inductive OptStringList where
  | none
  | some (ls : List String)

class ToOptStringList (α : Type) where
  toOptStringList : α → OptStringList

instance : ToOptStringList OptStringList where
  toOptStringList := id

-- Coerce List String directly
instance : ToOptStringList (List String) where
  toOptStringList := .some

-- Coerce Array String directly
instance : ToOptStringList (Array String) where
  toOptStringList a := .some a.toList

instance {α} [ToOptStringList α] : Coe α OptStringList where
  coe := ToOptStringList.toOptStringList

def myPrint (x : OptStringList := .none) : IO Unit :=
  match x with
  | .none => IO.println "none"
  | .some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
