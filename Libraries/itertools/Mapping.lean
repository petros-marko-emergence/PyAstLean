import Libraries.itertools.ItertoolsDef

namespace Libraries.itertools

/-- Map supported `itertools` members to the Lean runtime helpers they lower to. -/
def pythonItertoolsMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "pairwise" => some ``Libraries.itertools.pyPairwise
  | "chain"    => some ``Libraries.itertools.pyChain
  | _ => none

end Libraries.itertools
