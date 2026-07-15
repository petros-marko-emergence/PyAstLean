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

/-- Bind an assignment/loop/comprehension target to type `t`, distributing a tuple type over a
tuple target (`a, b = pair`). Only joins known facts in. -/
partial def bindTargetType (env : Env) (target : Json) (t : PyType) : Env :=
  match nodeTypeOf target with
  | some "Name" =>
      match nameId? target with
      | some n => if t == .unknown then env else env.insert n ((env.get? n |>.getD .unknown).join t)
      | none => env
  | some "Tuple" | some "List" =>
      let elts := (target.getObjValAs? (Array Json) "elts").toOption.getD #[]
      match t with
      | .tuple es => (Array.range elts.size).foldl (fun e i => bindTargetType e elts[i]! (es[i]?.getD .unknown)) env
      | _ => elts.foldl (fun e elt => bindTargetType e elt t.elemType) env
  | _ => env

/-- Bind every comprehension target in `json` (`[… for x in xs]`, `for a,b in zip(...)`) from its
iterable's element type, so a call inside the comprehension sees the target typed. -/
partial def compBindings (sigs : Sigs) (env : Env) (json : Json) : Env :=
  let env :=
    if ["ListComp", "SetComp", "DictComp", "GeneratorExp"].contains (nodeTypeOf json |>.getD "") then
      let gens := (json.getObjValAs? (Array Json) "generators").toOption.getD #[]
      gens.foldl (fun e gen =>
        match getField gen "target", getField gen "iter" with
        | some target, some iter => bindTargetType e target (typeOfExpr sigs e iter).elemType
        | _, _ => e) env
    else env
  match json with
  | .arr xs => xs.foldl (compBindings sigs) env
  | .obj fs => fs.toList.foldl (fun e (_, v) => compBindings sigs e v) env
  | _ => env

/-- Every statement in a body, flattened through nested blocks but not into nested `def`s. -/
private partial def flatStmts (stmts : List Json) : List Json :=
  stmts.foldl (fun acc s => acc ++ [s] ++ (childBlocks s).flatMap flatStmts) []

/-- The declared parameter names of `fn`, in order. -/
def paramNames (fn : Json) : Array String := Id.run do
  let mut names := #[]
  let .ok args := fn.getObjVal? "args" | return names
  let .ok argsArr := args.getObjValAs? (Array Json) "args" | return names
  for arg in argsArr do
    if let .ok name := arg.getObjValAs? String "arg" then names := names.push name
  return names

/-- Parameter name → annotated type for a `FunctionDef` (annotated params only). -/
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

/-- What `name`'s usage in one expression tells us — but only from **unambiguous** signals: a method
call whose name pins the receiver's type (`p.split()` → str, `p.append(x)` → list, `p.keys()` →
dict). Ambiguous uses (`p[i]`, `for x in p`, `len(p)` — any of list/str/dict) are deliberately left
`unknown` so a string parameter is never mis-typed as a list. -/
private partial def usageType (name : String) (json : Json) : PyType :=
  let here : PyType :=
    match nodeTypeOf json with
    | some "Call" =>
        match getField json "func" with
        | some func =>
            if nodeTypeOf func != some "Attribute" then .unknown else
            match (getField func "value").bind nameId? with
            | some n =>
                if n != name then .unknown else
                match (func.getObjValAs? String "attr").toOption with
                | some attr =>
                    if ["split", "rsplit", "splitlines", "upper", "lower", "strip", "lstrip",
                        "rstrip", "replace", "startswith", "endswith"].contains attr then .str
                    else if ["append", "pop", "sort", "reverse", "insert", "extend"].contains attr then .list .unknown
                    else if ["keys", "values", "items", "setdefault"].contains attr then .dict .unknown .unknown
                    else if ["add", "discard"].contains attr then .set .unknown
                    else .unknown
                | none => .unknown
            | none => .unknown
        | none => .unknown
    | _ => .unknown
  let sub := match json with
    | .arr xs => PyType.joinAll (xs.toList.map (usageType name))
    | .obj fs => PyType.joinAll (fs.toList.map (fun (_, v) => usageType name v))
    | _ => .unknown
  here.join sub

/-- Seed each unannotated parameter from unambiguous body usage (`p.split()` → str, `p.append()` →
list, `p.keys()` → dict). This is the safe part of the use-based inference the old Python pre-pass
did. -/
private def paramUsageSeed (fn : Json) : Env := Id.run do
  let body := fn.getObjValAs? (Array Json) "body" |>.toOption.getD #[]
  let mut env : Env := {}
  for name in paramNames fn do
    let t := usageType name (Json.arr body)
    if t != .unknown then env := env.insert name t
  return env

/-- Infer a type for every local in `fn`, reflowing to a fixpoint. `outer` seeds the environment
with the enclosing scope so a nested def's captures start typed; `hints` seeds unannotated
parameters with types learned from call sites; `sigs` resolves calls to user functions. Precedence:
enclosing captures > annotations > call-site hints > body-usage. -/
partial def inferFunction (sigs : Sigs) (outer hints : Env) (fn : Json) : Env := Id.run do
  let body := (fn.getObjValAs? (Array Json) "body").toOption.getD #[]
  let stmts := flatStmts body.toList
  -- body-usage is the weakest seed; call-site hints, then annotations, then captures override it.
  let seed := (paramSeed fn).fold (fun m k v => m.insert k v)
    (hints.fold (fun m k v => m.insert k v) (paramUsageSeed fn))
  let mut env := outer.fold (fun m k v => m.insert k v) seed
  let bodyJson := Json.arr body
  -- Reflow until stable. The lattice climbs, so a small cap is a sound floor, not a correctness risk.
  for _ in [0:8] do
    let next := compBindings sigs (stmts.foldl (applyStmt sigs) env) bodyJson
    if next.size == env.size && next.fold (fun ok k v => ok && (env.get? k |>.getD .unknown) == v) true then
      env := next
      break
    env := next
  return env

/-- The type `fn` returns: the join of every `return <e>` under its inferred environment. A bare
`return` (no value) or falling off the end contributes `None`. -/
partial def returnTypeOf (sigs : Sigs) (hints : Env) (fn : Json) : PyType := Id.run do
  let env := inferFunction sigs {} hints fn
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
                else match env.get? name with
                  -- A parameter used at genuinely different types (`.any`, e.g. `add(a,b)` called
                  -- with ints and strings) is boxed as `PyValue` so one definition dispatches on the
                  -- runtime tag. A fully-known type is stamped normally.
                  | some (.any) => arg.setObjVal! "_ty" (Json.mkObj [("node_type", .str "Name"), ("id", .str "PyValue")])
                  | some t => match toAnnotation? t with
                      | some ann => arg.setObjVal! "_ty" ann
                      | none => arg
                  | none => arg
            | _ => arg
          fn.setObjVal! "args" (args.setObjVal! "args" (Json.arr argsArr))
      | _ => fn
  | _ => fn

/-- Mark every `t[k]` where `t` is a pair-typed name (`tuple[a, b]`) with `_PastaLean_pair`, so the
subscript codegen projects `.1`/`.2` instead of `pyGetItem` (which has no instance for a
heterogeneous product). Does not descend into a nested `def` (separate scope, its own env). -/
partial def markTuples (env : Env) (json : Json) : Json :=
  if nodeTypeOf json == some "FunctionDef" then json
  else
    let json :=
      if nodeTypeOf json == some "Subscript" then
        match getField json "value" with
        | some v =>
            match (nameId? v).bind (env.get? ·) with
            | some (.tuple es) =>
                if es.length == 2 then json.setObjVal! "value" (v.setObjVal! "_PastaLean_pair" (Json.bool true))
                else json
            | _ => json
        | none => json
      else json
    match json with
    | .arr xs => Json.arr (xs.map (markTuples env))
    | .obj fs => Json.mkObj (fs.toList.map (fun (k, v) => (k, markTuples env v)))
    | _ => json

mutual

/-- Infer types for `fn` (seeded by `outer` captures and `hints` for unannotated params, resolving
calls with `sigs`), stamp its params and every binder in its body, and recurse into nested defs.
A function whose returns disagree (`.any`) and that has no return annotation is marked `_box_return`
so codegen boxes its result as `PyValue`. -/
partial def stampFunction (sigs : Sigs) (outer hints : Env) (fn : Json) : Json :=
  let env := inferFunction sigs outer hints fn
  let fn := stampParams env fn
  let fn := match fn.getObjValAs? String "name" with
    | .ok name =>
        -- The return type from its annotation if it has one (a union like `int | str` reads as
        -- `.any`), else the inferred one. `.any` means the returns genuinely disagree → box; a fully
        -- known type is stamped as `_ret_ty` so codegen can ascribe it (a recursive or effectful def
        -- needs its return type in the signature — this is what annotate_python's `-> T` provided).
        let annotated := match getField fn "returns" with | some r => !r.isNull | none => false
        let retType := if annotated then ofAnnotation ((getField fn "returns").getD Json.null)
                       else (sigs.get? name).getD .unknown
        if retType == (.any : PyType) then fn.setObjVal! "_box_return" (Json.bool true)
        else if !annotated && retType.isKnown then
          match toAnnotation? retType with
          | some ann => fn.setObjVal! "_ret_ty" ann
          | none => fn
        else fn
    | _ => fn
  match fn.getObjValAs? (Array Json) "body" with
  | .ok body => fn.setObjVal! "body" (Json.arr ((body.map (stampStmt sigs env)).map (markTuples env)))
  | _ => fn

/-- Stamp one statement: its target, its nested blocks, and any nested def. -/
partial def stampStmt (sigs : Sigs) (env : Env) (s : Json) : Json :=
  -- A nested def's params come from its own annotations or captured `outer`, not call-site hints.
  if nodeTypeOf s == some "FunctionDef" then stampFunction sigs env {} s
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

/-! ### Interprocedural: return types flow to call sites, argument types flow to parameters -/

/-- Inferred type of each parameter of each user function, by position. -/
abbrev ParamSigs := Std.HashMap String (Array PyType)

/-- Every top-level `FunctionDef` in a module or mutual group, in order. -/
private def topFunctions (module : Json) : Array Json :=
  ((module.getObjValAs? (Array Json) "body").toOption.getD #[]).filter
    (nodeTypeOf · == some "FunctionDef")

/-- The hint environment for `fn`'s parameters from `params` (its inferred per-position types). -/
private def hintsFor (params : ParamSigs) (fn : Json) : Env := Id.run do
  let names := paramNames fn
  let types := (params.get? ((fn.getObjValAs? String "name").toOption.getD "")).getD #[]
  let mut env : Env := {}
  for i in [0:names.size] do
    if let some t := types[i]? then if t != .unknown then env := env.insert names[i]! t
  return env

/-- Collect `(calleeName, argumentTypes)` for every direct call `foo(a, b, …)` in `json`, typing the
arguments under `env`. Nested calls are included; method calls are ignored (no positional callee). -/
private partial def collectCalls (sigs : Sigs) (env : Env) (json : Json) : Array (String × Array PyType) :=
  let here : Array (String × Array PyType) :=
    if nodeTypeOf json == some "Call" then
      match getField json "func" with
      | some func =>
          match (nodeTypeOf func, (func.getObjValAs? String "id").toOption) with
          | (some "Name", some name) =>
              let args := ((json.getObjValAs? (Array Json) "args").toOption.getD #[]).map (typeOfExpr sigs env)
              #[(name, args)]
          | _ => #[]
      | none => #[]
    else #[]
  let sub := match json with
    | .arr xs => xs.foldl (fun acc x => acc ++ collectCalls sigs env x) #[]
    | .obj fs => fs.toList.foldl (fun acc (_, v) => acc ++ collectCalls sigs env v) #[]
    | _ => #[]
  here ++ sub

/-- Join `argTypes` into `params[name]` position-by-position (missing positions start `unknown`). -/
private def refineParams (params : ParamSigs) (name : String) (arity : Nat) (argTypes : Array PyType) : ParamSigs :=
  let cur := (params.get? name).getD (Array.replicate arity .unknown)
  let next := (Array.range cur.size).map fun i =>
    (cur[i]!).join (argTypes[i]?.getD .unknown)
  params.insert name next

/-- Co-evolve every function's return type AND its parameter types to a fixpoint: a callee's return
flows to its callers, and a caller's argument types flow to the callee's parameters. Both only climb
the lattice, so this settles. -/
partial def collectSigs (module : Json) : Sigs × ParamSigs := Id.run do
  let fns := topFunctions module
  -- Seed each function's parameters with their annotations (unknown where unannotated).
  let mut params : ParamSigs := {}
  for fn in fns do
    if let .ok name := fn.getObjValAs? String "name" then
      let seed := paramSeed fn
      params := params.insert name ((paramNames fn).map fun p => (seed.get? p).getD .unknown)
  let mut sigs : Sigs := {}
  for _ in [0:6] do
    let mut nextSigs := sigs
    let mut nextParams := params
    for fn in fns do
      if let .ok name := fn.getObjValAs? String "name" then
        let hints := hintsFor params fn
        nextSigs := nextSigs.insert name (returnTypeOf sigs hints fn)
        -- refine callees' params from this function's call sites, typed under its own env.
        let env := inferFunction sigs {} hints fn
        for (callee, argTypes) in collectCalls sigs env fn do
          if params.contains callee then
            nextParams := refineParams nextParams callee argTypes.size argTypes
    let stable := nextSigs.size == sigs.size
      && nextSigs.fold (fun ok k v => ok && (sigs.get? k |>.getD .unknown) == v) true
      && nextParams.fold (fun ok k v => ok && (params.get? k |>.getD #[]) == v) true
    sigs := nextSigs; params := nextParams
    if stable then break
  return (sigs, params)

/-- Stamp `_ty` across one top-level node, resolving calls with `sigs` and seeding each function's
unannotated params from `params`. The driver sends one statement per request; a `FunctionDef`, a
`ClassDef` (each method) or a `Module` (a mutual group) is stamped, anything else is unchanged. -/
partial def stampNodeWith (sigs : Sigs) (params : ParamSigs) (s : Json) : Json :=
  match nodeTypeOf s with
  | some "FunctionDef" => stampFunction sigs {} (hintsFor params s) s
  | some "ClassDef" =>
      match s.getObjValAs? (Array Json) "body" with
      | .ok methods => s.setObjVal! "body" (Json.arr (methods.map fun m =>
          if nodeTypeOf m == some "FunctionDef" then stampFunction sigs {} (hintsFor params m) m else m))
      | _ => s
  | some "Module" =>
      match s.getObjValAs? (Array Json) "body" with
      | .ok body => s.setObjVal! "body" (Json.arr (body.map (stampNodeWith sigs params)))
      | _ => s
  | _ => s

/-- Intraprocedural stamping of a single node (no cross-function info). Used per-request as a
fallback; `inferModule` supersedes it when the whole module is available. -/
partial def stampNode (s : Json) : Json := stampNodeWith {} {} s

/-- Whole-module inference: co-evolve return and parameter types to a fixpoint, then stamp each
top-level node with that knowledge. This is what the `inferTypes` backend task runs. -/
def inferModule (module : Json) : Json :=
  let (sigs, params) := collectSigs module
  match module.getObjValAs? (Array Json) "body" with
  | .ok body => module.setObjVal! "body" (Json.arr (body.map (stampNodeWith sigs params)))
  | _ => stampNodeWith sigs params module

end TypeInfer
