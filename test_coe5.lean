instance : Coe (Array String) (Option (List String)) where
  coe a := some a.toList

instance : Coe (List String) (Option (List String)) where
  coe l := some l

def myPrint (x : Option (List String) := none) : IO Unit :=
  match x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
