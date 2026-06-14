import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

inductive OptStringList where
  | none
  | some (ls : List String)

instance : Coe (List String) OptStringList where
  coe := .some

instance : Coe (Array String) OptStringList where
  coe a := .some a.toList

instance [ToString α] : Coe (List α) OptStringList where
  coe a := .some (a.map toString)

instance [ToString α] : Coe (Array α) OptStringList where
  coe a := .some (a.map toString |>.toList)

def myPrint (x : OptStringList := .none) : IO Unit :=
  match x with
  | .none => IO.println "none"
  | .some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
  myPrint (x := [1, 2, 3])
  myPrint (x := #[4, 5, 6])
