import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

class PyIndexable (α : Type) where
  toIndex : α → List String

instance : PyIndexable (List String) where
  toIndex := id

instance : PyIndexable (Array String) where
  toIndex := Array.toList

instance {α β} [PyAstLean.PyIterable α β] [PyAstLean.PyPrintable β] : PyIndexable α where
  toIndex a := PyAstLean.pyIter a |>.map PyAstLean.PyPrintable.pyStringify

instance {α} [PyIndexable α] : Coe α (Option (List String)) where
  coe a := some (PyIndexable.toIndex a)

def myPrint (x : Option (List String) := none) : IO Unit :=
  match x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
  myPrint (x := #[1, 2, 3])
