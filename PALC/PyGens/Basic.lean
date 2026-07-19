import PastaLean.PyGens.Basic

open Lean

namespace PastaLean


/-- info: 3 -/
#guard_msgs in
#eval 1 +ₚ 2

/-- info: "Hello, World!" -/
#guard_msgs in
#eval "Hello, " +ₚ "World!"


/--
info: def PastaLean.fn : ℕ → IO ℕ :=
fun n ↦
  have this :=
    have m := n + 1;
    pure m;
  this
-/
#guard_msgs in
#print fn


/-- info: 4 -/
#guard_msgs in
#eval fn 3

/-- info: PastaLean.fn (n : ℕ) : IO ℕ -/
#guard_msgs in
#check fn


/-- info: 4 -/
#guard_msgs in
#eval let m : Nat := n₀; m + (1 : Nat)

set_option pp.all true in

/--
info: def PastaLean.fnId : Nat :=
@Id.run.{0} Nat
  (have n : Nat := @OfNat.ofNat.{0} Nat (nat_lit 3) (instOfNatNat (nat_lit 3));
  have m : Nat :=
    @HAdd.hAdd.{0, 0, 0} Nat Nat Nat (@instHAdd.{0} Nat instAddNat) n
      (@OfNat.ofNat.{0} Nat (nat_lit 1) (instOfNatNat (nat_lit 1)));
  @Pure.pure.{0, 0} Id.{0} (@Applicative.toPure.{0, 0} Id.{0} (@Monad.toApplicative.{0, 0} Id.{0} Id.instMonad.{0})) Nat
    m)
-/
#guard_msgs in
#print fnId


/--
info: Try this:
  [apply] (1 : Int) +ₚ (2 : Int)
---
info: 3
-/
#guard_msgs in
#eval py_term% onePlusTwoNode



/--
info: "{\"left\":{\"node_type\":\"Constant\",\"value\":1},\"node_type\":\"BinOp\",\"op\":\"add\",\"right\":{\"node_type\":\"Constant\",\"value\":2}}"
-/
#guard_msgs in
#eval onePlusTwoNode.compress

def stringNatBinOpNode := json% {
    "node_type": "BinOp",
    "op": "add",
    "left": {
      "node_type": "Constant",
      "value": "Hello"
    },
    "right": {
      "node_type": "Constant",
      "value": 2
    }
  }

/--
info: "Error generating code: Error in code generation function PastaLean.binOpSyntax for key 'BinOp' and syntax category 'term': Error elaborating code: failed to synthesize instance of type class\n  PastaLean.PyHAdd String ℤ ?m.4\n\nHint: Type class instance resolution failures can be inspected with the `set_option trace.Meta.synthInstance true` command. for \"Hello\" +ₚ (2 : Int)"
-/
#guard_msgs in
#eval show CoreM String from do
  match ← getCodeCore stringNatBinOpNode `term with
  | .ok fmt => return s!"unexpected success: {fmt}"
  | .error err => return err

/--
info: Try this:
  [apply] (1 : Int)
---
info: 1
-/
#guard_msgs in
#eval py_term% js₀

/--
info: Try this:
  [apply] "Hello, World!"
---
info: "Hello, World!"
-/
#guard_msgs in
#eval py_term% {
  "node_type": "Constant",
  "value": "Hello, World!"
}

/--
info: Try this:
  [apply] (-15 : Rat) / 10
---
info: -3 / 2
-/
#guard_msgs in
#eval py_term% {
  "node_type": "Constant",
  "value": -1.5
}

/--
info: Try this:
  [apply] (1 : Int) +ₚ (2 : Int)
---
info: 3
-/
#guard_msgs in
#eval py_term% json% {
    "node_type": "BinOp",
    "op": "add",
    "left": {
      "node_type": "Constant",
      "value": 1
    },
    "right": {
      "node_type": "Constant",
      "value": 2
    }
  }

/--
info: Try this:
  [apply] "three" *ₚ (4 : Int)
---
info: "threethreethreethree"
-/
#guard_msgs in
#eval py_term% json% {
    "node_type": "BinOp",
    "op": "mul",
    "left": {
      "node_type": "Constant",
      "value": "three"
    },
    "right": {
      "node_type": "Constant",
      "value": 4
    }
  }

end PastaLean
