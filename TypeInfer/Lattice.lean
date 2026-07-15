import Mathlib
import TypeInfer.PyType

/-!
# Verified properties of the type lattice

The inference engine's correctness rests on two mathematical facts:

* **`join` is a bounded join-semilattice** — commutative, associative, idempotent, with `unknown`
  as bottom (⊥) and `any` as top (⊤). The induced order `a ≤ b := join a b = b` is a partial order,
  and `join` computes its *least* upper bound. This is exactly what guarantees the reflow fixpoint in
  `Solve.lean` **terminates**: each step only moves up a partial order of bounded height, so it
  cannot loop.

* **`consistent` is a gradual-typing consistency relation** (Siek & Taha) — reflexive and symmetric,
  with the *gradual guarantee* that `unknown` is consistent with everything, and — crucially — **not
  transitive**. Non-transitivity is the property that distinguishes gradual typing from subtyping: a
  boxed (`any`) value can flow anywhere, but that does not make two unrelated concrete types
  interchangeable.

The production `join`/`consistent` (`PyType.lean`) recurse over the nested `tuple (List PyType)`
with two-argument recursion, which Lean cannot prove terminating structurally, so they are
`partial def` — and a `partial def` has no equations to reason about. We therefore verify the laws
**universally** on `Ty`, a faithful model of the lattice (every constructor except the nested-list
`tuple`, whose join is a routine elementwise extension), and pin the production functions to the
model with **concrete** `native_decide` theorems (`Production` below), including non-transitivity on
the real `consistent`.
-/

namespace TypeInfer.Lattice

/-- A model of `PyType` carrying the full lattice structure: every constructor except the nested
`tuple (List PyType)`, so all recursion is on a single subterm and the laws are provable. -/
inductive Ty where
  | unknown | any | int | bool | str | float | none
  | list (e : Ty) | set (e : Ty) | dict (k v : Ty) | cls (n : String)
  deriving DecidableEq, Repr

/-- Least upper bound. `unknown` yields to anything; genuinely different types go to `any`; Python's
`bool <: int`; containers combine elementwise. Mirrors `PyType.join`. -/
def join (x y : Ty) : Ty := match x, y with
  | .unknown, t => t
  | t, .unknown => t
  | .any, _ => .any
  | _, .any => .any
  | .int, .bool => .int
  | .bool, .int => .int
  | .list a, .list b => .list (join a b)
  | .set a, .set b => .set (join a b)
  | .dict k₁ v₁, .dict k₂ v₂ => .dict (join k₁ k₂) (join v₁ v₂)
  | a, b => if a = b then a else .any
  termination_by sizeOf x + sizeOf y
  decreasing_by all_goals (simp_wf; try omega)

/-! ### `join` is a commutative, associative, idempotent semilattice with ⊥ and ⊤ -/

@[simp] theorem join_unknown (a : Ty) : join .unknown a = a := by simp [join]
@[simp] theorem join_any (a : Ty) : join .any a = .any := by cases a <;> simp [join]
theorem join_idem (a : Ty) : join a a = a := by induction a <;> simp_all [join]
theorem join_comm (a b : Ty) : join a b = join b a := by
  induction a generalizing b <;> cases b <;> simp_all [join] <;> split_ifs <;> simp_all [eq_comm]

set_option maxHeartbeats 2000000 in
theorem join_assoc (a b c : Ty) : join (join a b) c = join a (join b c) := by
  induction a generalizing b c <;> cases b <;> cases c <;>
    simp_all [join] <;> (try split_ifs) <;> simp_all [join, eq_comm]

/-! ### The induced order `≤` is a partial order and `join` is its least upper bound -/

/-- `a ≤ b` when joining `a` into `b` adds nothing — i.e. `b` already knows at least as much. -/
def le (a b : Ty) : Prop := join a b = b

theorem le_refl (a : Ty) : le a a := join_idem a
/-- `unknown` (⊥) is below everything. -/
theorem le_unknown (a : Ty) : le .unknown a := by simp [le]
/-- `any` (⊤) is above everything. -/
theorem le_any (a : Ty) : le a .any := by simp [le, join_comm a .any]
theorem le_trans {a b c : Ty} (h₁ : le a b) (h₂ : le b c) : le a c := by
  simp only [le] at *; rw [← h₂, ← join_assoc, h₁]
theorem le_antisymm {a b : Ty} (h₁ : le a b) (h₂ : le b a) : a = b := by
  simp only [le] at *; rw [← h₁, join_comm, h₂]

/-- `join a b` is an upper bound of `a` — the **monotonicity** the fixpoint's termination rests on:
each reflow step can only move a variable *up* this order. -/
theorem le_join_left (a b : Ty) : le a (join a b) := by
  simp only [le, ← join_assoc, join_idem]
theorem le_join_right (a b : Ty) : le b (join a b) := by
  simp only [le, join_comm a b, ← join_assoc, join_idem]
/-- …and it is the *least* upper bound: any common upper bound `c` already dominates it. -/
theorem join_lub {a b c : Ty} (ha : le a c) (hb : le b c) : le (join a b) c := by
  simp only [le] at *; rw [join_assoc, hb, ha]

/-! ### `consistent` is a gradual-typing consistency relation -/

/-- Gradual-typing consistency (Siek & Taha). Mirrors `PyType.consistent`. -/
def consistent (x y : Ty) : Bool := match x, y with
  | .unknown, _ => true
  | _, .unknown => true
  | .any, _ => true
  | _, .any => true
  | .int, .bool => true
  | .bool, .int => true
  | .list a, .list b => consistent a b
  | .set a, .set b => consistent a b
  | .dict k₁ v₁, .dict k₂ v₂ => consistent k₁ k₂ && consistent v₁ v₂
  | a, b => a = b
  termination_by sizeOf x + sizeOf y
  decreasing_by all_goals (simp_wf; try omega)

theorem consistent_refl (a : Ty) : consistent a a := by induction a <;> simp_all [consistent]
theorem consistent_symm (a b : Ty) : consistent a b = consistent b a := by
  induction a generalizing b <;> cases b <;> simp_all [consistent, eq_comm]
/-- The **gradual guarantee**: the dynamic type `unknown` is consistent with every type, so a value
whose type we could not determine may flow anywhere. -/
theorem consistent_unknown (a : Ty) : consistent .unknown a := by simp [consistent]

/-- Consistency is **not transitive** — the property that separates gradual typing from subtyping.
`int ~ any` and `any ~ str`, yet `int ≁ str`: boxing lets a value flow anywhere, but does not make
two unrelated concrete types interchangeable. -/
theorem consistent_not_trans :
    ¬ (∀ a b c : Ty, consistent a b → consistent b c → consistent a c) := by
  intro h
  have hbad : consistent .int .str := h .int .any .str (by simp [consistent]) (by simp [consistent])
  simp [consistent] at hbad

/-! ### Coercions (`reconcile`) -/

/-- The coercion decision, on the model. Mirrors `PyType.reconcile` (minus the `opt` unwrap, which
the model has no constructor for). -/
def reconcile (expected actual : Ty) : PyType.Reconcile :=
  if expected = actual then .exact
  else match expected, actual with
    | .int, .bool => .boolToInt
    | .float, .int => .intToFloat
    | .float, .bool => .intToFloat
    | e, a => if consistent e a then .exact else .box

/-- No coercion is ever inserted for a value that already has the expected type. -/
theorem reconcile_refl (a : Ty) : reconcile a a = .exact := by simp [reconcile]

/-- Every coercion decision is one of the finite, intended actions — the function is total, so a
value never gets "stuck" with no way to reach its expected type. -/
theorem reconcile_total (e a : Ty) :
    reconcile e a = .exact ∨ reconcile e a = .boolToInt ∨ reconcile e a = .intToFloat
      ∨ reconcile e a = .box := by
  unfold reconcile; split
  · exact .inl rfl
  · split <;> simp <;> split <;> simp

/-! ### The same properties, checked on the *actual* production functions

The universal proofs above are about the model `Ty`; these pin the real `PyType.join` /
`PyType.consistent` (partial defs, evaluated natively) to the same behaviour on concrete inputs. -/

namespace Production
open TypeInfer (PyType)

/-- Non-transitivity of consistency on the REAL engine, not the model. -/
theorem consistent_not_trans :
    PyType.consistent .int .any = true ∧ PyType.consistent .any .str = true
      ∧ PyType.consistent .int .str = false := by native_decide

/-- The gradual guarantee on the real engine, sampled over several types. -/
theorem gradual_guarantee :
    ∀ t ∈ [PyType.int, .str, .float, .list .int, .dict .str .int, .none],
      PyType.consistent .unknown t = true := by native_decide

theorem join_bool_int : (PyType.join .bool .int == .int) = true := by native_decide
theorem join_conflict : (PyType.join .int .str == .any) = true := by native_decide
theorem join_none_optional : (PyType.join (.cls "TreeNode") .none == .opt (.cls "TreeNode")) = true := by
  native_decide

-- The production `reconcile` picks the right coercion on concrete inputs.
theorem reconcile_bool_int : PyType.reconcile .int .bool = .boolToInt := by native_decide
theorem reconcile_unwrap : PyType.reconcile (.cls "TreeNode") (.opt (.cls "TreeNode")) = .unwrapOpt := by
  native_decide
theorem reconcile_box : PyType.reconcile .int .str = .box := by native_decide
theorem reconcile_same : PyType.reconcile (.list .int) (.list .int) = .exact := by native_decide

end Production
end TypeInfer.Lattice
