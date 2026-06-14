import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

instance {α} [PyAstLean.PyPrintable α] : Coe (List α) (Option (List String)) where
  coe l := some (l.map PyAstLean.PyPrintable.pyStringify)

instance {α} [PyAstLean.PyPrintable α] : Coe (Array α) (Option (List String)) where
  coe a := some (a.toList.map PyAstLean.PyPrintable.pyStringify)

def myPrint (x : Option (List String) := none) : IO Unit :=
  match x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #[(1:Int), 2])
