import TypeInfer.PyType
import TypeInfer.Annotation
import TypeInfer.Value

/-!
# Typing rules

Two functions drive the fixpoint in `Solve.lean`:

* `typeOfExpr env e` — the type of an expression, using what we already know about the variables
  in `env`. (`ofValue` in `Value.lean` only sees a literal's shape; this also follows names, calls,
  subscripts and operators.)
* `applyStmt env s` — how one statement updates what we know. An assignment *learns* a type; a
  mutation like `xs.append(3)` teaches us `xs` holds ints even though `xs` started as `[]`.

Both only ever `join` new facts in, so the env climbs the lattice and the fixpoint terminates.
-/

namespace TypeInfer

open Lean

abbrev Env := Std.HashMap String PyType

private def nodeType? (j : Json) : Option String := (j.getObjValAs? String "node_type").toOption
private def field (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption
private def eltsOf (j : Json) : List Json := ((j.getObjValAs? (Array Json) "elts").toOption.getD #[]).toList

/-- A subscript index that is a non-negative integer literal, for static tuple projection. -/
def literalIndex? (slice : Json) : Option Nat :=
  if nodeType? slice == some "Constant" then
    match slice.getObjVal? "value" with
    | .ok (.num ⟨m, 0⟩) => if m ≥ 0 then some m.toNat else none
    | _ => none
  else none

/-- The result type of arithmetic `a ⊕ b` (as opposed to `join`, which is "same slot, two types").
`+` concatenates strings and lists; on numbers it promotes toward `float`. -/
def arith : PyType → PyType → PyType
  | .str, .str => .str
  | .list a, .list b => .list (a.join b)
  | a, b =>
      if a.isNumeric && b.isNumeric then
        if a == .float || b == .float then .float else .int
      else .unknown

/-- Builtins whose result type is fixed regardless of the argument. -/
private def constReturnBuiltins : List (String × PyType) :=
  [ ("len", .int), ("ord", .int), ("int", .int), ("str", .str), ("input", .str),
    ("bool", .bool), ("float", .float), ("chr", .str), ("hash", .int),
    ("bin", .str), ("hex", .str), ("oct", .str) ]

/-- Methods whose result type is fixed regardless of the receiver. -/
private def constReturnMethods : List (String × PyType) :=
  [ ("split", .list .str), ("rsplit", .list .str), ("splitlines", .list .str),
    ("join", .str), ("strip", .str), ("lstrip", .str), ("rstrip", .str),
    ("lower", .str), ("upper", .str), ("replace", .str), ("format", .str),
    ("count", .int), ("find", .int), ("rfind", .int), ("index", .int),
    ("startswith", .bool), ("endswith", .bool), ("isdigit", .bool), ("isalpha", .bool) ]

mutual

/-- The type of an expression under the current environment. Total: `unknown` when unsure. -/
partial def typeOfExpr (env : Env) (e : Json) : PyType :=
  match nodeType? e with
  | some "Name" => ((e.getObjValAs? String "id").toOption.bind (env.get? ·)).getD .unknown
  | some "Constant" => ofValue e
  | some "List" => .list (PyType.joinAll ((eltsOf e).map (typeOfExpr env)))
  | some "Set" => .set (PyType.joinAll ((eltsOf e).map (typeOfExpr env)))
  | some "Tuple" => .tuple ((eltsOf e).map (typeOfExpr env))
  | some "Dict" =>
      let entries := ((e.getObjValAs? (Array Json) "entries").toOption.getD #[]).toList
      let part (k : String) := entries.map fun en => (field en k).elim .unknown (typeOfExpr env)
      .dict (PyType.joinAll (part "key")) (PyType.joinAll (part "value"))
  | some "Range" => .list .int
  | some "BinOp" =>
      match field e "left", field e "right" with
      | some l, some r =>
          let lt := typeOfExpr env l
          let rt := typeOfExpr env r
          match (e.getObjValAs? String "op").toOption with
          -- `[0] * n` / `n * [0]` repeats a list; every other `*` is arithmetic.
          | some "mul" =>
              match lt, rt with
              | .list _, _ => lt
              | _, .list _ => rt
              | _, _ => arith lt rt
          -- Python's `/` is always true division, so `int / int` is a `float`.
          | some "div" => .float
          | _ => arith lt rt
      | _, _ => .unknown
  | some "UnaryOp" =>
      if (e.getObjValAs? String "op").toOption == some "not" then .bool
      else (field e "operand").elim .unknown (typeOfExpr env)
  | some "Compare" => .bool
  | some "BoolOp" =>
      -- `a and b` / `a or b` evaluate to one operand, so the type is their join.
      PyType.joinAll (((e.getObjValAs? (Array Json) "values").toOption.getD #[]).toList.map (typeOfExpr env))
  | some "IfExp" =>
      match field e "body", field e "orelse" with
      | some b, some o => (typeOfExpr env b).join (typeOfExpr env o)
      | _, _ => .unknown
  | some "Subscript" =>
      match field e "value" with
      | some c =>
          let ct := typeOfExpr env c
          match ct with
          -- `t[k]` for a literal index projects the k-th element; otherwise the elements join.
          | .tuple es =>
              match (field e "slice").bind literalIndex? with
              | some i => es[i]?.getD (PyType.joinAll es)
              | none => PyType.joinAll es
          -- `d[k]` yields the value; `xs[i]` / `s[i]` yield the element.
          | .dict _ v => v
          | _ => ct.elemType
      | none => .unknown
  | some "Call" => typeOfCall env e
  | _ => .unknown

/-- The type a call returns. -/
partial def typeOfCall (env : Env) (e : Json) : PyType :=
  let args := ((e.getObjValAs? (Array Json) "args").toOption.getD #[]).toList
  match field e "func" with
  | some func =>
      match nodeType? func with
      | some "Name" =>
          match (func.getObjValAs? String "id").toOption with
          | some name => builtinReturn env name args
          | none => .unknown
      | some "Attribute" =>
          match (func.getObjValAs? String "attr").toOption with
          | some attr => methodReturn env attr (field func "value") args
          | none => .unknown
      | _ => .unknown
  | none => .unknown

/-- Return type of a builtin `name(args)`. Unknown for user functions (P2 resolves those). -/
partial def builtinReturn (env : Env) (name : String) (args : List Json) : PyType :=
  match constReturnBuiltins.lookup name with
  | some t => t
  | none =>
      let arg0 := args.head?.elim .unknown (typeOfExpr env)
      match name with
      | "range" => .list .int
      | "list" | "sorted" | "reversed" => .list arg0.elemType
      | "set" | "frozenset" => .set arg0.elemType
      | "tuple" => .list arg0.elemType
      | "dict" => arg0
      | "abs" | "min" | "max" | "sum" =>
          -- element for the container forms, else the argument itself.
          if args.length == 1 && arg0.elemType != .unknown then arg0.elemType else arg0
      | _ => .unknown

/-- Return type of `recv.attr(args)`. -/
partial def methodReturn (env : Env) (attr : String) (recv : Option Json) (_args : List Json) : PyType :=
  match constReturnMethods.lookup attr with
  | some t => t
  | none =>
      let recvT := recv.elim .unknown (typeOfExpr env)
      match attr with
      | "keys" => .list (match recvT with | .dict k _ => k | _ => .unknown)
      | "values" => .list (match recvT with | .dict _ v => v | _ => .unknown)
      | "items" => .list (match recvT with | .dict k v => .tuple [k, v] | _ => .unknown)
      | "get" | "pop" | "setdefault" =>
          match recvT with | .dict _ v => v | _ => recvT.elemType
      | "copy" => recvT
      | _ => .unknown

end

end TypeInfer
