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
class PyAnys (α : Type) (ν : outParam Type) where
  pyAnys : α → List ν

/-- Public runtime surface for Python `values()`. -/
def pyAnys {α ν : Type} [inst : PyAnys α ν] (m : α) : List ν :=
  inst.pyAnys m

instance [BEq κ] [Hashable κ] : PyItems (Std.HashMap κ ν) κ ν where
  pyItems m := pyDictItems m

instance [BEq κ] [Hashable κ] : PyKeys (Std.HashMap κ ν) κ where
  pyKeys m := pyDictKeys m

instance [BEq κ] [Hashable κ] : PyAnys (Std.HashMap κ ν) ν where
  pyAnys m := pyDictValues m

end PastaLean
