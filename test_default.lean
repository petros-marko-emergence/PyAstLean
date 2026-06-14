import PyAstLean.PyAPI.Core
import PyAstLean.PyAPI.CommonProtocols.Iterable
import PyAstLean.PyAPI.PyPrint

class IntoStringList (α : Type) where
  toList : α → Option (List String)

instance : IntoStringList Unit where
  toList _ := none

instance {α β} [PyAstLean.PyIterable α β] [PyAstLean.PyPrintable β] : IntoStringList α where
  toList a := some (PyAstLean.pyIter a |>.map PyAstLean.PyPrintable.pyStringify)

def myPrint {α} [IntoStringList α] (x : α := ()) : Option (List String) :=
  IntoStringList.toList x

#eval myPrint
#eval myPrint (x := ["hi", "there"])
