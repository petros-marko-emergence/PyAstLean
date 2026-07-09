import Mathlib
import PastaLean.PyAPI.Dicts

namespace PastaLean

/-- Protocol for Python-style `items()`. -/
class PyItems (α : Type) (κ ν : outParam Type) where
  pyItems : α → List (κ × ν)

/-- Public runtime surface for Python `items()`. -/
def pyItems {α κ ν : Type} [inst : PyItems α κ ν] (m : α) : List (κ × ν) :=
  inst.pyItems m

/-- Protocol for Python-style `keys()`. -/
class PyKeys (α : Type) (κ : outParam Type) where
  pyKeys : α → List κ

/-- Public runtime surface for Python `keys()`. -/
def pyKeys {α κ : Type} [inst : PyKeys α κ] (m : α) : List κ :=
  inst.pyKeys m

/-- Protocol for Python-style `values()`. -/
class PyValues (α : Type) (ν : outParam Type) where
  pyValues : α → List ν

/-- Public runtime surface for Python `values()`. -/
def pyValues {α ν : Type} [inst : PyValues α ν] (m : α) : List ν :=
  inst.pyValues m

instance [BEq κ] [Hashable κ] : PyItems (Std.HashMap κ ν) κ ν where
  pyItems m := pyDictItems m

instance [BEq κ] [Hashable κ] : PyKeys (Std.HashMap κ ν) κ where
  pyKeys m := pyDictKeys m

instance [BEq κ] [Hashable κ] : PyValues (Std.HashMap κ ν) ν where
  pyValues m := pyDictValues m

end PastaLean
