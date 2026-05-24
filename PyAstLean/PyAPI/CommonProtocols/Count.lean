import Mathlib
import PyAstLean.PyAPI.Strings
import PyAstLean.PyAPI.Lists
import PyAstLean.PyAPI.Dicts

namespace PyAstLean

class PyCount (α β: Type) where
  /-- For `count()`, return the number of occurrences of the given element. -/
  pyCount : α → β → Int

/- Public runtime for `count()`-/
def pyCount {α β} [PyCount α β] : α → β → Int :=
  PyCount.pyCount

instance : PyCount String String where
  pyCount := pyStringCount

instance [DecidableEq α] : PyCount (List α) α where
  pyCount := pyListCount

end PyAstLean
