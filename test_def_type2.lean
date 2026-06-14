class PyIndexable (α : Type) where
  toIndex : α → Option (List String)

instance : PyIndexable Unit where
  toIndex _ := none

instance : PyIndexable (Array String) where
  toIndex a := some a.toList

def myPrint {M : Type} [PyIndexable M] (x : M := ()) : IO Unit :=
  match PyIndexable.toIndex x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := #["hi", "there"])
