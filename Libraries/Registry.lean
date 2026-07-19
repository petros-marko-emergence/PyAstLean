import Lean
import Libraries.Mutator
import Libraries.bisect.Mapping
import Libraries.collections.Mapping
import Libraries.functools.Mapping
import Libraries.heapq.Mapping
import Libraries.itertools.Mapping
import Libraries.math.Mapping
import Libraries.string.Mapping
import Libraries.numpy.Mapping
import Libraries.passta.Mapping
import Libraries.scipy.Mapping
import Libraries.pandas.Mapping

namespace Libraries

/--
Registry mapping imported Python library members to Lean runtime functions/constants.

This plays the same role for imported libraries that `PastaLean.Attributes` plays for
Python methods: codegen consults this table once an AST node has been recognized as
coming from a specific imported module.
-/
def pythonLibraryMap? (moduleName member : String) : Option Lean.Name :=
  match moduleName with
  | "bisect" => bisect.pythonBisectMemberMap? member
  | "collections" => collections.pythonCollectionsMemberMap? member
  | "functools" => functools.pythonFunctoolsMemberMap? member
  | "heapq" => heapq.pythonHeapqMemberMap? member
  | "itertools" => itertools.pythonItertoolsMemberMap? member
  | "math" => math.pythonMathMemberMap? member
  | "string" => string.pythonStringMemberMap? member
  | "numpy" => numpy.pythonNumpyMemberMap? member
  | "passta" => passta.pythonPasstaMemberMap? member
  | "scipy" => scipy.pythonScipyMemberMap? member
  | "pandas" => pandas.pythonPandasMemberMap? member
  | _ => none

/--
Exact-mode (`ℝ`, `noncomputable`) registry for transcendental library members.

In the default numeric mode codegen consults this first; a hit lowers `math.exp` etc. to the
`Real.*`-backed version (provable, not runnable). A miss falls back to `pythonLibraryMap?` (the
regular, often `Float`-valued, mapping) — so non-transcendental members are unaffected.
-/
def pythonLibraryMapReal? (moduleName member : String) : Option Lean.Name :=
  match moduleName with
  | "math" => math.pythonMathMemberMapReal? member
  | "numpy" => numpy.pythonNumpyMemberMapReal? member
  | "scipy" => scipy.pythonScipyMemberMapReal? member
  | _ => none

/-- Exact-mode overrides that are computable + provable but NOT transcendental `ℝ` (e.g.
`math.pow` with an integer exponent → rational power). Consulted in exact mode after the real map
and before the regular (`Float`) map. -/
def pythonLibraryMapExact? (moduleName member : String) : Option Lean.Name :=
  match moduleName with
  | "math" => math.pythonMathMemberMapExact? member
  | _ => none

/-- Return type of a library member, for TypeInfer — the single entry point, so `TypeInfer` names no
specific library. numpy is field-polymorphic, hence a function of the first argument's type. -/
def libraryMemberReturn? (moduleName member : String) (arg0 : TypeInfer.PyType) :
    Option TypeInfer.PyType :=
  match moduleName with
  | "math" => math.mathMemberReturn? member
  | "scipy" => scipy.scipyMemberReturn? member
  | "numpy" => (numpy.numpyMemberReturn? member).map (· arg0)
  | _ => none

/-- The in-place mutation spec of a library member, for the core codegen — one entry point, so
codegen names no specific library. -/
def libraryMutator? (moduleName member : String) : Option LibraryMutator :=
  match moduleName with
  | "heapq" => heapq.heapqMutator? member
  | _ => none

end Libraries
