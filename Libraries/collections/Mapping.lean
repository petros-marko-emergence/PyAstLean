import Libraries.collections.CollectionsDef

namespace Libraries.collections

/-- Map supported `collections` members to the Lean runtime helpers they lower to.

`Counter`/`defaultdict` are normally claimed earlier by their special-call lowerer, which picks the
right constant from the call's arity and factory argument. These entries cover the leftover
one-argument `Counter(xs)` shape. -/
def pythonCollectionsMemberMap? (member : String) : Option Lean.Name :=
  match member with
  | "Counter" => some ``Libraries.collections.pyCounter
  | _ => none

end Libraries.collections
