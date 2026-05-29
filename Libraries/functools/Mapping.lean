import Libraries.functools.FunctoolsDef

namespace Libraries.functools

/-- Map supported `functools` members to the Lean runtime helpers they lower to. -/
def pythonFunctoolsMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "reduce" => some ``Libraries.functools.pyReduce
  | _ => none

end Libraries.functools
