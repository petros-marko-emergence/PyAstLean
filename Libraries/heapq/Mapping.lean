import Libraries.heapq.HeapqDef
import Libraries.Mutator

namespace Libraries.heapq

/-- Map the pure `heapq` members (return a value, no mutation) to their runtime helpers. The mutating
members (`heapify`/`heappush`/`heappop`) are declared in `heapqMutator?` below and lowered generically
by the core codegen. -/
def pythonHeapqMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "nsmallest" => some ``Libraries.heapq.pyNsmallest
  | "nlargest"  => some ``Libraries.heapq.pyNlargest
  | _ => none

/-- The `heapq` members that mutate their heap argument in place. -/
def heapqMutator? (member : String) : Option Libraries.LibraryMutator :=
  match member with
  | "heapify"  => some { stmtFn := ``pyHeapify }
  | "heappush" => some { stmtFn := ``pyHeappush }
  | "heappop"  => some { stmtFn := ``pyHeappopRest, valueRest? := some (``pyHeappopVal, ``pyHeappopRest) }
  | _ => none

end Libraries.heapq
