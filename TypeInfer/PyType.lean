import Lean

/-!
# The type lattice

`PyType` is what PastaLean knows about a Python value. It is a lattice with two special elements:

* `unknown` (⊥) — nothing known *yet*. Joining it with anything yields that thing.
* `any` (⊤) — conflicting information. `int` on one path and `str` on another joins to `any`,
  which is the signal to box the value as `PyAny`.

`join` is the least upper bound: start every slot at `unknown` and join in what the program says
about it until nothing changes. This is the classic reflow-to-fixpoint of PyPy's RPython annotator
and Shed Skin.
-/

namespace TypeInfer

/-- What PastaLean knows about a Python value. -/
inductive PyType where
  /-- Nothing known yet — the lattice bottom. -/
  | unknown
  /-- Conflicting types — the lattice top. Boxed as `PyAny`. -/
  | any
  | int
  | bool
  | str
  /-- Python `float`. Lowers to `ℚ`, `ℝ` or `Float` depending on the numeric mode. -/
  | float
  /-- The type of `None`. -/
  | none
  | list  (elem : PyType)
  | set   (elem : PyType)
  | tuple (elems : List PyType)
  | dict  (key val : PyType)
  /-- `Optional[T]` — `T` or `None`. -/
  | opt   (inner : PyType)
  /-- A user class, `TreeNode`, `ListNode`, … -/
  | cls   (name : String)
  deriving Inhabited, Repr

namespace PyType

partial def beq : PyType → PyType → Bool
  | .unknown, .unknown | .any, .any | .int, .int | .bool, .bool
  | .str, .str | .float, .float | .none, .none => true
  | .list a, .list b | .set a, .set b | .opt a, .opt b => beq a b
  | .dict k₁ v₁, .dict k₂ v₂ => beq k₁ k₂ && beq v₁ v₂
  | .cls a, .cls b => a == b
  | .tuple as, .tuple bs =>
      as.length == bs.length && (as.zip bs).all fun (a, b) => beq a b
  | _, _ => false

instance : BEq PyType := ⟨beq⟩

def toString : PyType → String
  | .unknown => "?"
  | .any => "Any"
  | .int => "int"
  | .bool => "bool"
  | .str => "str"
  | .float => "float"
  | .none => "None"
  | .list e => s!"list[{toString e}]"
  | .set e => s!"set[{toString e}]"
  | .dict k v => s!"dict[{toString k}, {toString v}]"
  | .opt i => s!"Optional[{toString i}]"
  | .cls n => n
  | .tuple es => "tuple[" ++ String.intercalate ", " (es.map toString) ++ "]"

instance : ToString PyType := ⟨toString⟩

/-- True when the type is fully determined, so a Lean type can be emitted for it. -/
partial def isKnown : PyType → Bool
  | .unknown | .any => false
  | .list e | .set e | .opt e => isKnown e
  | .dict k v => isKnown k && isKnown v
  | .tuple es => es.all isKnown
  | _ => true

/-- Should a *local* binding of this type be ascribed at all? Only discrete scalars, where an
unascribed literal would otherwise default (`5` → `ℚ` in exact mode). Containers/floats are left for
Lean to infer from the assignment RHS, so an ascription never *forces* an element type (e.g. `ℚ`)
against what the RHS actually elaborates to (e.g. a numpy `Float`). Parameters are ascribed
separately — this governs only locals. -/
def needsAscription : PyType → Bool
  | .int | .bool | .str => true
  | _ => false

/-- Least upper bound.

`unknown` carries no information, so it yields to anything. Genuinely incompatible types (`int` and
`str`) go to `any`. `bool` joins into `int` because Python's `bool` is a subclass of `int`
(`True + 1 = 2`), and `None` joins into `Optional`.
-/
partial def join : PyType → PyType → PyType
  | .unknown, t | t, .unknown => t
  | .any, _ | _, .any => .any
  -- `bool <: int` in Python.
  | .int, .bool | .bool, .int => .int
  | .none, .none => .none
  -- `opt` before `none`, or `None ⊔ Optional[int]` would nest to `Optional[Optional[int]]`.
  | .opt a, .opt b => .opt (join a b)
  | .opt a, .none | .none, .opt a => .opt a
  | .opt a, b | b, .opt a => .opt (join a b)
  | .none, t | t, .none => .opt t
  | .list a, .list b => .list (join a b)
  | .set a, .set b => .set (join a b)
  | .dict k₁ v₁, .dict k₂ v₂ => .dict (join k₁ k₂) (join v₁ v₂)
  | .tuple as, .tuple bs =>
      if as.length == bs.length then .tuple ((as.zip bs).map fun (a, b) => join a b)
      else .any
  | a, b => if a.beq b then a else .any

/-- Join a whole list, starting from `unknown`. -/
def joinAll (ts : List PyType) : PyType := ts.foldl join .unknown

/-- Gradual-typing *consistency* (Siek & Taha): reflexive and symmetric, **not** transitive.
`any` is consistent with everything, so a boxed value may flow anywhere; `int` and `str` are not
consistent with each other. -/
partial def consistent : PyType → PyType → Bool
  | .any, _ | _, .any | .unknown, _ | _, .unknown => true
  | .int, .bool | .bool, .int => true
  | .list a, .list b | .set a, .set b | .opt a, .opt b => consistent a b
  | .opt a, b | b, .opt a => b.beq .none || consistent a b
  | .dict k₁ v₁, .dict k₂ v₂ => consistent k₁ k₂ && consistent v₁ v₂
  | .tuple as, .tuple bs =>
      as.length == bs.length && (as.zip bs).all fun (a, b) => consistent a b
  | a, b => a.beq b

/-- Is this a number Python arithmetic accepts? -/
def isNumeric : PyType → Bool
  | .int | .bool | .float => true
  | _ => false

/-- The element type an iterable yields, or `unknown`. Strings iterate as one-character strings. -/
def elemType : PyType → PyType
  | .list e | .set e => e
  | .str => .str
  | .dict k _ => k
  | .tuple es => joinAll es
  | _ => .unknown

/-- What to do when a value of type `actual` reaches a position expecting `expected`: the small
implicit coercion Python performs, or `box` (fall back to `PyAny`) when the types are unrelated. -/
inductive Reconcile where
  /-- Types already agree — no coercion. -/
  | exact
  /-- `actual` is `bool`, `expected` is `int` — `True` is `1` (`pyBoolToInt`). -/
  | boolToInt
  /-- `actual` is an integer, `expected` is `float` — widen `Int → Rat`. -/
  | intToFloat
  /-- `actual` is `Optional[T]`, `expected` is `T` — unwrap the `Option`. -/
  | unwrapOpt
  /-- Unrelated types — box both as `PyAny`. -/
  | box
  deriving Repr, BEq, DecidableEq

namespace Reconcile end Reconcile

/-- Decide the coercion from `actual` to `expected`. The wired-up cases today are `boolToInt`
(runtime instances), tuple projection (codegen) and `box` (`PyAny`); `intToFloat`/`unwrapOpt`
name the remaining ones. -/
def reconcile (expected actual : PyType) : Reconcile :=
  if expected.beq actual then .exact
  else match expected, actual with
    | .int, .bool => .boolToInt
    | .float, .int | .float, .bool => .intToFloat
    | t, .opt u => if t.beq u then .unwrapOpt else .box
    | e, a => if consistent e a then .exact else .box

end PyType
end TypeInfer
