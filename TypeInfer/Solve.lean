import TypeInfer.Rules

/-!
# The intraprocedural fixpoint

`inferFunction` works out a type for every local in one function: seed the parameters from their
annotations, then walk the body over and over — learning a little more each pass — until nothing
changes. Because every update only `join`s upward, the environment can only climb the lattice, so
it settles.

`stampTypes` then writes each settled type back onto the IR as a `_ty` field on the binder
(parameters, assignment targets, `for` targets), where the code generator reads it.

Nested `def`s are handled by seeding their inference with the enclosing function's environment, so a
captured variable already has a type when the helper is lifted out.
-/

namespace TypeInfer

open Lean

private def nodeTypeOf (j : Json) : Option String := (j.getObjValAs? String "node_type").toOption
private def getField (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption
private def nameId? (j : Json) : Option String :=
  if nodeTypeOf j == some "Name" then (j.getObjValAs? String "id").toOption else none

/-- The statement lists nested directly in `s` (`if`/`for`/`while`/`with`/`try` blocks), not
descending into a nested `def`/`class` (those have their own scope). -/
private def childBlocks (s : Json) : List (List Json) := Id.run do
  if nodeTypeOf s == some "FunctionDef" || nodeTypeOf s == some "ClassDef" then return []
  let mut blocks := #[]
  for f in #["body", "orelse", "finalbody"] do
    if let .ok elems := s.getObjValAs? (Array Json) f then blocks := blocks.push elems.toList
  if let .ok handlers := s.getObjValAs? (Array Json) "handlers" then
    for h in handlers do
      if let .ok elems := h.getObjValAs? (Array Json) "body" then blocks := blocks.push elems.toList
  return blocks.toList

/-- A bare `container.append/add(v)` statement, teaching the container's element type. -/
def applyMutation (sigs : Sigs) (env : Env) (value : Json) : Env :=
  if nodeTypeOf value != some "Call" then env else
  match getField value "func" with
  | some func =>
      if nodeTypeOf func != some "Attribute" then env else
      match (func.getObjValAs? String "attr").toOption, (getField func "value").bind nameId? with
      | some attr, some cname =>
          let args := ((value.getObjValAs? (Array Json) "args").toOption.getD #[]).toList
          let elemFrom (i : Nat) : PyType := (args[i]?).elim .unknown (typeOfExpr sigs env)
          let learned : PyType := match attr with
            | "append" | "add" | "insert" => .list (elemFrom (if attr == "insert" then 1 else 0))
            | "extend" => match args[0]?.elim .unknown (typeOfExpr sigs env) with
                          | .list e => .list e
                          | _ => .unknown
            | _ => .unknown
          if learned == .unknown then env
          else env.insert cname ((env.get? cname |>.getD .unknown).join learned)
      | _, _ => env
  | none => env

/-- Update the environment with what one statement teaches us. Only ever `join`s facts in. -/
def applyStmt (sigs : Sigs) (env : Env) (s : Json) : Env :=
  let learn (env : Env) (name : String) (t : PyType) : Env :=
    if t == .unknown then env else env.insert name ((env.get? name |>.getD .unknown).join t)
  match nodeTypeOf s with
  | some "AnnAssign" =>
      match (getField s "target").bind nameId?, getField s "annotation" with
      | some name, some ann => env.insert name (ofAnnotation ann)   -- an explicit annotation wins
      | _, _ => env
  | some "Assign" =>
      match getField s "target", getField s "value" with
      | some target, some value =>
          match nameId? target with
          | some name => learn env name (typeOfExpr sigs env value)
          -- `xs[i] = v` teaches the element/value type of the container `xs`.
          | none =>
              if nodeTypeOf target == some "Subscript" then
                match (getField target "value").bind nameId? with
                | some cname =>
                    let vt := typeOfExpr sigs env value
                    let learned := match env.get? cname |>.getD .unknown with
                      | .dict _ _ => .dict ((getField target "slice").elim .unknown (typeOfExpr sigs env)) vt
                      | _ => .list vt
                    learn env cname learned
                | none => env
              else env
      | _, _ => env
  | some "AugAssign" =>
      match (getField s "target").bind nameId?, getField s "value" with
      | some name, some value => learn env name (arith (env.get? name |>.getD .unknown) (typeOfExpr sigs env value))
      | _, _ => env
  | some "For" =>
      match (getField s "target").bind nameId?, getField s "iter" with
      | some name, some iter => learn env name (typeOfExpr sigs env iter).elemType
      | _, _ => env
  -- `xs.append(v)` / `xs.add(v)` teaches that `xs` holds values of `v`'s type.
  | some "Expr" =>
      match getField s "value" with
      | some value => applyMutation sigs env value
      | none => env
  | _ => env

/-- Every statement in a body, flattened through nested blocks but not into nested `def`s. -/
private partial def flatStmts (stmts : List Json) : List Json :=
  stmts.foldl (fun acc s => acc ++ [s] ++ (childBlocks s).flatMap flatStmts) []

/-- Parameter name → annotated type for a `FunctionDef`. -/
private def paramSeed (fn : Json) : Env := Id.run do
  let mut env : Env := {}
  let .ok args := fn.getObjVal? "args" | return env
  let .ok argsArr := args.getObjValAs? (Array Json) "args" | return env
  for arg in argsArr do
    if let .ok name := arg.getObjValAs? String "arg" then
      match getField arg "annotation" with
      | some ann => if !ann.isNull then env := env.insert name (ofAnnotation ann)
      | none => pure ()
  return env

/-- Infer a type for every local in `fn`, reflowing to a fixpoint. `outer` seeds the environment
with the enclosing scope so a nested def's captures start typed; `sigs` resolves calls to user
functions. -/
partial def inferFunction (sigs : Sigs) (outer : Env) (fn : Json) : Env := Id.run do
  let body := (fn.getObjValAs? (Array Json) "body").toOption.getD #[]
  let stmts := flatStmts body.toList
  let mut env := outer.fold (fun m k v => m.insert k v) (paramSeed fn)
  -- Reflow until stable. The lattice climbs, so a small cap is a sound floor, not a correctness risk.
  for _ in [0:8] do
    let next := stmts.foldl (applyStmt sigs) env
    if next.size == env.size && next.fold (fun ok k v => ok && (env.get? k |>.getD .unknown) == v) true then
      env := next
      break
    env := next
  return env

/-- The type `fn` returns: the join of every `return <e>` under its inferred environment. A bare
`return` (no value) or falling off the end contributes `None`. -/
partial def returnTypeOf (sigs : Sigs) (fn : Json) : PyType := Id.run do
  let env := inferFunction sigs {} fn
  let body := (fn.getObjValAs? (Array Json) "body").toOption.getD #[]
  let mut ret : PyType := .unknown
  for s in flatStmts body.toList do
    if nodeTypeOf s == some "Return" then
      match getField s "value" with
      | some v => if !v.isNull then ret := ret.join (typeOfExpr sigs env v) else ret := ret.join .none
      | none => ret := ret.join .none
  return ret

/-! ### Writing the inferred types back onto the IR as `_ty` -/

/-- Stamp `_ty` (an annotation node) on a target if we know a fully-determined type for it, unless a
`_ty` is already present (the interprocedural pass stamps first; a later intraprocedural pass must
not clobber its richer result). Tuple targets stamp each element. -/
partial def stampTarget (env : Env) (target : Json) : Json :=
  match nodeTypeOf target with
  | some "Name" =>
      if (getField target "_ty").isSome then target
      else
        -- `_` is a throwaway; typing it is pointless and can clash with its RHS.
        match (nameId? target).filter (· != "_") |>.bind (env.get? ·) |>.bind toAnnotation? with
        | some ann => target.setObjVal! "_ty" ann
        | none => target
  | some "Tuple" | some "List" =>
      match target.getObjValAs? (Array Json) "elts" with
      | .ok elts => target.setObjVal! "elts" (Json.arr (elts.map (stampTarget env)))
      | _ => target
  | _ => target

/-- Add `_ty` to each unannotated parameter we could type (a nested capture, or a rare
un-hinted param). An explicit annotation, or an existing `_ty`, always wins. -/
private def stampParams (env : Env) (fn : Json) : Json :=
  match fn.getObjVal? "args" with
  | .ok args =>
      match args.getObjValAs? (Array Json) "args" with
      | .ok argsArr =>
          let argsArr := argsArr.map fun arg =>
            match arg.getObjValAs? String "arg" with
            | .ok name =>
                let annotated := match getField arg "annotation" with
                  | some a => !a.isNull
                  | none => false
                if annotated || (getField arg "_ty").isSome then arg
                else match (env.get? name).bind toAnnotation? with
                  | some ann => arg.setObjVal! "_ty" ann
                  | none => arg
            | _ => arg
          fn.setObjVal! "args" (args.setObjVal! "args" (Json.arr argsArr))
      | _ => fn
  | _ => fn

mutual

/-- Infer types for `fn` (seeded by `outer`, resolving calls with `sigs`), stamp its params and
every binder in its body, and recurse into nested defs with the now-known environment. -/
partial def stampFunction (sigs : Sigs) (outer : Env) (fn : Json) : Json :=
  let env := inferFunction sigs outer fn
  let fn := stampParams env fn
  match fn.getObjValAs? (Array Json) "body" with
  | .ok body => fn.setObjVal! "body" (Json.arr (body.map (stampStmt sigs env)))
  | _ => fn

/-- Stamp one statement: its target, its nested blocks, and any nested def. -/
partial def stampStmt (sigs : Sigs) (env : Env) (s : Json) : Json :=
  if nodeTypeOf s == some "FunctionDef" then stampFunction sigs env s
  else Id.run do
    let mut s := s
    match nodeTypeOf s with
    | some "Assign" | some "AnnAssign" | some "AugAssign" | some "For" =>
        if let some t := getField s "target" then s := s.setObjVal! "target" (stampTarget env t)
    | _ => pure ()
    for f in #["body", "orelse", "finalbody"] do
      if let .ok elems := s.getObjValAs? (Array Json) f then
        s := s.setObjVal! f (Json.arr (elems.map (stampStmt sigs env)))
    if let .ok handlers := s.getObjValAs? (Array Json) "handlers" then
      let handlers := handlers.map fun h =>
        match h.getObjValAs? (Array Json) "body" with
        | .ok elems => h.setObjVal! "body" (Json.arr (elems.map (stampStmt sigs env)))
        | _ => h
      s := s.setObjVal! "handlers" (Json.arr handlers)
    return s

end

/-! ### Interprocedural: a function's return type flows to its call sites -/

/-- Every top-level `FunctionDef` in a module or mutual group, in order. -/
private def topFunctions (module : Json) : Array Json :=
  ((module.getObjValAs? (Array Json) "body").toOption.getD #[]).filter
    (nodeTypeOf · == some "FunctionDef")

/-- Compute each function's return type, reflowing to a fixpoint so a caller sees a callee's type.
Return types only climb the lattice, so this settles. -/
partial def collectSigs (module : Json) : Sigs := Id.run do
  let fns := topFunctions module
  let mut sigs : Sigs := {}
  for _ in [0:6] do
    let mut next := sigs
    for fn in fns do
      if let .ok name := fn.getObjValAs? String "name" then
        next := next.insert name (returnTypeOf sigs fn)
    if next.size == sigs.size && next.fold (fun ok k v => ok && (sigs.get? k |>.getD .unknown) == v) true then
      sigs := next
      break
    sigs := next
  return sigs

/-- Stamp `_ty` across one top-level node, resolving calls with `sigs`. The driver sends one
statement per request; a `FunctionDef`, a `ClassDef` (each method) or a `Module` (a mutual group)
is stamped, anything else is returned unchanged. -/
partial def stampNodeWith (sigs : Sigs) (s : Json) : Json :=
  match nodeTypeOf s with
  | some "FunctionDef" => stampFunction sigs {} s
  | some "ClassDef" =>
      match s.getObjValAs? (Array Json) "body" with
      | .ok methods => s.setObjVal! "body" (Json.arr (methods.map fun m =>
          if nodeTypeOf m == some "FunctionDef" then stampFunction sigs {} m else m))
      | _ => s
  | some "Module" =>
      match s.getObjValAs? (Array Json) "body" with
      | .ok body => s.setObjVal! "body" (Json.arr (body.map (stampNodeWith sigs)))
      | _ => s
  | _ => s

/-- Intraprocedural stamping of a single node (no cross-function info). Used per-request as a
fallback; `inferModule` supersedes it when the whole module is available. -/
partial def stampNode (s : Json) : Json := stampNodeWith {} s

/-- Whole-module inference: compute every function's return type to a fixpoint, then stamp each
top-level node with that knowledge. This is what the `inferTypes` backend task runs. -/
def inferModule (module : Json) : Json :=
  let sigs := collectSigs module
  match module.getObjValAs? (Array Json) "body" with
  | .ok body => module.setObjVal! "body" (Json.arr (body.map (stampNodeWith sigs)))
  | _ => stampNodeWith sigs module

end TypeInfer
