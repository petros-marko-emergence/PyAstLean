import TypeInfer.PyType

/-!
# The type of a value expression

`ofValue` reads the type straight off an expression's shape: `0` is an `int`, `[0] * n` is a
`list[int]`, `{"a": 1}` is a `dict[str, int]`. Anything whose shape does not determine a type — a
bare name, a call — is `unknown`, which the fixpoint pass fills in later.

This is the single source of truth for "what does this literal look like". Three copies of it used
to live in `ClosureConvert.lean`, `CallShared.lean` and `node_visitor.py`.
-/

namespace TypeInfer

open Lean

private def nodeType? (json : Json) : Option String :=
  (json.getObjValAs? String "node_type").toOption

private def elts (json : Json) : List Json :=
  ((json.getObjValAs? (Array Json) "elts").toOption.getD #[]).toList

/-- The type of a Python constant. `2` is an `int`, `2.0` a `float` — the IR keeps them apart with
`python_literal_kind`, because JSON has one number type. -/
private def ofConstant (json : Json) : PyType :=
  match json.getObjVal? "value" with
  | .ok (.bool _) => .bool
  | .ok (.str _) => .str
  | .ok .null => .none
  | .ok (.num ⟨_, exponent⟩) =>
      if (json.getObjValAs? String "python_literal_kind").toOption == some "float" then .float
      else if exponent == 0 then .int
      else .float
  | _ => .unknown

/-- The type of an expression, as far as its shape reveals it. Total: `unknown` when unclear. -/
partial def ofValue (json : Json) : PyType :=
  match nodeType? json with
  | some "Constant" => ofConstant json
  | some "List" => .list (PyType.joinAll ((elts json).map ofValue))
  | some "Set" => .set (PyType.joinAll ((elts json).map ofValue))
  | some "Tuple" => .tuple ((elts json).map ofValue)
  | some "Dict" =>
      let entries := ((json.getObjValAs? (Array Json) "entries").toOption.getD #[]).toList
      let part (key : String) : List PyType :=
        entries.map fun e => (e.getObjVal? key).toOption.elim .unknown ofValue
      .dict (PyType.joinAll (part "key")) (PyType.joinAll (part "value"))
  -- `[0] * n` and `n * [0]` build a list; every other `*` is arithmetic.
  | some "BinOp" =>
      if (json.getObjValAs? String "op").toOption == some "mul" then
        match json.getObjVal? "left", json.getObjVal? "right" with
        | .ok left, .ok right =>
            if nodeType? left == some "List" then ofValue left
            else if nodeType? right == some "List" then ofValue right
            else .unknown
        | _, _ => .unknown
      else .unknown
  | _ => .unknown

end TypeInfer
