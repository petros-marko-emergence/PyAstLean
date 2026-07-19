import PastaLean.PyGens.Calls.CallEffects
import PastaLean.PyGens.Calls.CallShared

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-- Lower a library mutator used AS A STATEMENT (`heapq.heappush(h, x)`, `heapify(h)`, or a discarded
`heappop(h)`) to a reassignment of its first-argument variable — `h := stmtFn h …`. The spec comes
from `Libraries` (`libraryMutatorOf?`), so no library names appear here. Only a plain-variable first
argument is supported; anything else falls through to the generic path. -/
def lowerLibraryMutatorDoElem? (funcJson : Json) (argsArray : Array Json) (argsCodes : Array (TSyntax `term))
    (_kw : PyKeywordArgs) : PygenM (Option (TSyntax `doElem)) := do
  let some spec := libraryMutatorOf? funcJson | return none
  unless argsArray.size ≥ 1 && jsonNodeType? argsArray[0]! == some "Name" do return none
  let hIdent ← getCode argsArray[0]! `ident
  let fn := mkIdent spec.stmtFn
  return some (← `(doElem| $hIdent:ident := $fn $argsCodes*))

end PastaLean
