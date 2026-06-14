inductive PyStringListArg where
  | none
  | some (ls : List String)

instance : Coe (List String) PyStringListArg where
  coe := PyStringListArg.some

instance : Coe (Array String) PyStringListArg where
  coe a := PyStringListArg.some a.toList

def myPrint (x : PyStringListArg := .none) : IO Unit :=
  match x with
  | .none => IO.println "none"
  | .some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := #["hi", "there"])
