import Libraries.heapq.HeapqDef

namespace Libraries.heapq

/-- Map the pure `heapq` members (return a value, no mutation) to their runtime helpers. The mutating
members (`heapify`/`heappush`/`heappop`) are lowered by the itertools-style special handler in
`PyGens/Calls/SpecialCalls/Heapq.lean`, not here. -/
def pythonHeapqMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "nsmallest" => some ``Libraries.heapq.pyNsmallest
  | "nlargest"  => some ``Libraries.heapq.pyNlargest
  | _ => none

end Libraries.heapq
