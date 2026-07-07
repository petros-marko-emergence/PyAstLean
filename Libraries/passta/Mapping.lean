import Mathlib
import Libraries.passta.PasstaDef

namespace Libraries.passta

/-- Library-local registry for contract helper members. -/
def pythonPasstaMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "Requires"  => some ``pyPassRequires
  | "Ensures"   => some ``pyPassEnsures
  | "Invariant" => some ``pyPassInvariant
  | "Assume"    => some ``pyPassAssume
  | "Assert"    => some ``pyPassAssert
  | "Decreases" => some ``pyPassDecreases
  | _ => none

end Libraries.passta
