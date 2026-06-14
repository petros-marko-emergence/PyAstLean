import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

class PyIndexable (α : Type) where
  toIndex : α → Option (List String)

instance : PyIndexable Unit where
  toIndex _ := none

instance : PyIndexable (List String) where
  toIndex := some

instance : PyIndexable (Array String) where
  toIndex a := some a.toList

instance {α β} [PyAstLean.PyIterable α β] [PyAstLean.PyPrintable β] : PyIndexable α where
  toIndex a := some (PyAstLean.pyIter a |>.map PyAstLean.PyPrintable.pyStringify)

def myPrint {M} [PyIndexable M] (x : M := ()) : IO Unit :=
  match PyIndexable.toIndex x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
  myPrint (x := #[1, 2, 3])
