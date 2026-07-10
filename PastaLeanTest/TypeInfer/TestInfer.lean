import TypeInfer

/-! Unit checks for the typing rules and the fixpoint. Each `#guard` fails the build if false. -/

open Lean TypeInfer
open TypeInfer.PyType (join)

/-! ### IR builders (matching what `node_visitor.py` emits) -/

private def name (id : String) : Json := Json.mkObj [("node_type", .str "Name"), ("id", .str id)]
private def const (v : Json) (kind : String := "") : Json :=
  let base := [("node_type", Json.str "Constant"), ("value", v)]
  Json.mkObj (if kind.isEmpty then base else base ++ [("python_literal_kind", .str kind)])
private def listOf (elts : List Json) : Json :=
  Json.mkObj [("node_type", .str "List"), ("elts", Json.arr elts.toArray)]
private def binop (op : String) (l r : Json) : Json :=
  Json.mkObj [("node_type", .str "BinOp"), ("op", .str op), ("left", l), ("right", r)]
private def call (fn : Json) (args : List Json) : Json :=
  Json.mkObj [("node_type", .str "Call"), ("func", fn), ("args", Json.arr args.toArray), ("keywords", Json.arr #[])]
private def attr (recv : Json) (a : String) : Json :=
  Json.mkObj [("node_type", .str "Attribute"), ("value", recv), ("attr", .str a)]
private def subscript (c i : Json) : Json :=
  Json.mkObj [("node_type", .str "Subscript"), ("value", c), ("slice", i)]

private def envOf (kvs : List (String × PyType)) : Env :=
  kvs.foldl (fun m (k, v) => m.insert k v) (Std.HashMap.emptyWithCapacity)

/-! ### `typeOfExpr` — expression typing under an environment -/

-- Name lookup (the case whose double-read bug made every lookup fail).
#guard typeOfExpr {} (envOf [("x", .int)]) (name "x") == PyType.int
#guard typeOfExpr {} (envOf []) (name "x") == PyType.unknown

-- Arithmetic promotes; `int + int` stays int (not ℚ), `int + float` is float.
#guard typeOfExpr {} (envOf [("x", .int)]) (binop "add" (name "x") (const (.num 1))) == PyType.int
#guard typeOfExpr {} (envOf [("x", .float)]) (binop "add" (name "x") (const (.num 1))) == PyType.float
-- Python `/` is true division: `int / int` is a `float`, never an `int`.
#guard typeOfExpr {} (envOf [("x", .int)]) (binop "div" (name "x") (const (.num 2))) == PyType.float
#guard typeOfExpr {} (envOf [("x", .int)]) (binop "floordiv" (name "x") (const (.num 2))) == PyType.int
-- `[0] * n` is a list, not arithmetic.
#guard typeOfExpr {} (envOf [("n", .int)]) (binop "mul" (listOf [const (.num 0)]) (name "n")) == .list .int
#guard typeOfExpr {} (envOf [("n", .int)]) (binop "mul" (const (.num 2)) (name "n")) == PyType.int

-- Subscript reads the element / value type.
#guard typeOfExpr {} (envOf [("xs", .list .str)]) (subscript (name "xs") (const (.num 0))) == PyType.str
#guard typeOfExpr {} (envOf [("d", .dict .str .int)]) (subscript (name "d") (const (.str "k"))) == PyType.int

-- Builtins and methods.
#guard typeOfExpr {} (envOf [("xs", .list .int)]) (call (name "len") [name "xs"]) == PyType.int
#guard typeOfExpr {} (envOf []) (call (name "range") [const (.num 5)]) == .list .int
#guard typeOfExpr {} (envOf [("s", .str)]) (call (attr (name "s") "split") [const (.str ",")]) == .list .str
#guard typeOfExpr {} (envOf [("d", .dict .str .int)]) (call (attr (name "d") "get") [const (.str "k")]) == PyType.int
#guard typeOfExpr {} (envOf [("d", .dict .str .int)]) (call (attr (name "d") "items") []) == .list (.tuple [.str, .int])

/-! ### `applyStmt` — how a statement updates the environment -/

private def assign (target value : Json) : Json :=
  Json.mkObj [("node_type", .str "Assign"), ("target", target), ("value", value)]
private def exprStmt (value : Json) : Json :=
  Json.mkObj [("node_type", .str "Expr"), ("value", value)]

-- `xs = []` then `xs.append(3)` teaches `xs : list[int]` even though the literal was empty.
#guard
  let e0 := applyStmt {} (envOf []) (assign (name "xs") (listOf []))
  let e1 := applyStmt {} e0 (exprStmt (call (attr (name "xs") "append") [const (.num 3)]))
  e1.get? "xs" == some (.list .int)

-- `d = {}` then `d["k"] = 5` teaches `d : dict[str, int]`.
#guard
  let e0 := applyStmt {} (envOf []) (assign (name "d")
    (Json.mkObj [("node_type", .str "Dict"), ("entries", Json.arr #[])]))
  let e1 := applyStmt {} e0 (assign (subscript (name "d") (const (.str "k"))) (const (.num 5)))
  e1.get? "d" == some (.dict .str .int)

-- `for i in range(n)` binds `i : int`.
#guard
  (applyStmt {} (envOf []) (Json.mkObj
    [("node_type", .str "For"), ("target", name "i"), ("iter", call (name "range") [name "n"])])).get? "i"
  == some PyType.int

-- Conflicting assignments join to `any`, which is left unstamped (no wrong type ascribed).
#guard
  let e0 := applyStmt {} (envOf []) (assign (name "v") (const (.num 1)))
  let e1 := applyStmt {} e0 (assign (name "v") (const (.str "s")))
  e1.get? "v" == some PyType.any

-- A call resolves through `sigs`: if `helper` returns `str`, then `x = helper()` gives `x : str`.
#guard
  let sigs : Sigs := (Std.HashMap.emptyWithCapacity).insert "helper" .str
  typeOfExpr sigs (envOf []) (call (name "helper") []) == PyType.str
-- A builtin still wins over `sigs` (a user function named `len` can't hijack the builtin).
#guard
  let sigs : Sigs := (Std.HashMap.emptyWithCapacity).insert "len" .str
  typeOfExpr sigs (envOf [("xs", .list .int)]) (call (name "len") [name "xs"]) == PyType.int

/-! ### `collectSigs` — a function's return type, to a fixpoint -/

private def funcDef (fname : String) (body : List Json) : Json :=
  Json.mkObj [("node_type", .str "FunctionDef"), ("name", .str fname),
    ("args", Json.mkObj [("args", Json.arr #[])]), ("body", Json.arr body.toArray)]
private def ret (v : Json) : Json := Json.mkObj [("node_type", .str "Return"), ("value", v)]
private def module (fns : List Json) : Json :=
  Json.mkObj [("node_type", .str "Module"), ("body", Json.arr fns.toArray)]

-- `producer` returns a list[int]; `consumer` returns `producer()`, so it too is list[int]
-- (the type flows across the call, resolved by the module fixpoint).
#guard
  let producer := funcDef "producer" [ret (listOf [const (.num 1)])]
  let consumer := funcDef "consumer" [ret (call (name "producer") [])]
  let sigs := collectSigs (module [producer, consumer])
  sigs.get? "consumer" == some (.list .int)
