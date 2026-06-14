import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

instance {α β} [PyAstLean.PyIterable α β] [PyAstLean.PyPrintable β] : Coe α (Option (List String)) where
  coe a := some (PyAstLean.pyIter a |>.map PyAstLean.PyPrintable.pyStringify)

def myPrint (x : Option (List String) := none) : IO Unit :=
  match x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #[(1:Int), 2])
