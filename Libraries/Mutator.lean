import Lean

namespace Libraries

/-- How a library member mutates its FIRST argument in place, declared BY the library so the core
code generator can lower it without hardcoding any library's names (the mutation analogue of
`pythonLibraryMap?`). A call `f(x, …)`:
* as a statement lowers to `x := stmtFn x …`;
* as `y = f(x, …)`, when `valueRest?` is set, lowers to `y := valFn x …; x := restFn x …`. -/
structure LibraryMutator where
  stmtFn : Lean.Name
  valueRest? : Option (Lean.Name × Lean.Name) := none

end Libraries
