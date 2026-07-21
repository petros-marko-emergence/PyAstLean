import Libraries.bisect.BisectDef

namespace Libraries.bisect

/-- Map supported `bisect` members to the Lean runtime helpers they lower to. -/
def pythonBisectMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "bisect_left"  => some ``Libraries.bisect.pyBisectLeft
  | "bisect_right" => some ``Libraries.bisect.pyBisectRight
  -- CPython exports `bisect` as an alias of `bisect_right`.
  | "bisect"       => some ``Libraries.bisect.pyBisectRight
  | _ => none

end Libraries.bisect
