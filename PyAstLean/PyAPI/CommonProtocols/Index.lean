import Mathlib
import PyAstLean.PyAPI.Strings
import PyAstLean.PyAPI.Lists

namespace PyAstLean
class PyIndex (α β: Type) where
  /-- For `index()`, return the index of the first occurrence of the given element. -/
  pyIndex : α → β → Int

/- Public runtime for `index()`-/
def pyIndex {α β} [PyIndex α β] : α → β → Int :=
  PyIndex.pyIndex

instance [DecidableEq α] : PyIndex (List α) α where
  pyIndex := pyListIndex

instance : PyIndex String String where
  pyIndex := pyStringIndex

end PyAstLean
