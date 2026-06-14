inductive OptStringList where
  | none
  | some (ls : List String)

instance : Coe (List String) OptStringList where
  coe := .some

instance : Coe (Array String) OptStringList where
  coe a := .some a.toList

def myPrint (x : OptStringList := .none) : IO Unit :=
  match x with
  | .none => IO.println "none"
  | .some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
