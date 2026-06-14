instance {α} [ToString α] : Coe (List α) (Option (List String)) where
  coe l := some (l.map toString)

instance {α} [ToString α] : Coe (Array α) (Option (List String)) where
  coe a := some (a.toList.map toString)

def myPrint (x : Option (List String) := none) : IO Unit :=
  match x with
  | none => IO.println "none"
  | some ls => IO.println (toString ls)

def main : IO Unit := do
  myPrint
  myPrint (x := ["hi", "there"])
  myPrint (x := [1, 2, 3])
  myPrint (x := #[(1 : Int), 2, 3])
