import PastaLean.PyGens.Core.Utils

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-!
## Closure conversion

A nested Python `def` lowers to `let f := fun …`, which is **not** recursive, so `dfs(i+1, j)`
inside `dfs` is an unknown identifier. Lean offers no local fix: `let rec` cannot be `partial` (so a
non-structural recursion fails termination checking), and a `where` clause forces `partial` onto the
*enclosing* def, which would cost it its unfolding and its `[simp, taste_ingr]` tag.

So each nested `def` becomes a sibling top-level `partial def` whose captured variables are extra
parameters. The enclosing function stays an ordinary, provable `def`.

`closureConvertFunction` lifts outermost-first: a nested def's captures become its parameters, so a
def one level deeper can capture them in turn. `def a: def b: def c` needs no special case.

Captured names the helper *mutates* (rebind, `x[i] = v`, `x.append(…)`) cannot be threaded yet, so
those are rejected with a clear error rather than silently dropped.
-/

/-- Append `x` unless it is already present, preserving first-seen order. -/
private def pushUnique (xs : Array String) (x : String) : Array String :=
  if xs.contains x then xs else xs.push x

private def appendUnique (xs ys : Array String) : Array String :=
  ys.foldl pushUnique xs

/-- The statement blocks nested directly inside `stmt` (`if`/`for`/`while`/`try` bodies). -/
private def nestedBlocks (stmt : Json) : Array (Array Json) := Id.run do
  let mut blocks := #[]
  for field in #["body", "orelse", "finalbody"] do
    if let .ok elems := stmt.getObjValAs? (Array Json) field then
      blocks := blocks.push elems
  if let .ok handlers := stmt.getObjValAs? (Array Json) "handlers" then
    for handler in handlers do
      if let .ok elems := handler.getObjValAs? (Array Json) "body" then
        blocks := blocks.push elems
  return blocks

/-- Every `Name` id appearing anywhere in `json`. -/
partial def jsonNameIds (json : Json) : Array String :=
  let here :=
    match jsonNodeType? json, json.getObjValAs? String "id" with
    | some "Name", .ok id => #[id]
    | _, _ => #[]
  match json with
  | .arr elems => elems.foldl (fun acc e => appendUnique acc (jsonNameIds e)) here
  | .obj fields => fields.toList.foldl (fun acc (_, v) => appendUnique acc (jsonNameIds v)) here
  | _ => here

/-- The names an assignment/loop target binds (a bare name, or the elements of a tuple unpack).
A `Subscript`/`Attribute` target mutates but does not bind. -/
partial def targetBoundNames (target : Json) : Array String :=
  match jsonNodeType? target with
  | some "Name" =>
      match target.getObjValAs? String "id" with
      | .ok id => #[id]
      | _ => #[]
  | some "Tuple" | some "List" =>
      match target.getObjValAs? (Array Json) "elts" with
      | .ok elts => elts.foldl (fun acc e => appendUnique acc (targetBoundNames e)) #[]
      | _ => #[]
  | _ => #[]

/-- The names `stmt` binds in the scope that contains it. -/
private def stmtBoundNames (stmt : Json) : Array String :=
  match jsonNodeType? stmt with
  | some "Assign" | some "AugAssign" | some "AnnAssign" | some "For" =>
      match stmt.getObjVal? "target" with
      | .ok target => targetBoundNames target
      | _ => #[]
  | some "FunctionDef" | some "ClassDef" =>
      match stmt.getObjValAs? String "name" with
      | .ok name => #[name]
      | _ => #[]
  | _ => #[]

/-- Names bound anywhere in a function body, not descending into a nested function's own scope. -/
partial def bodyBoundNames (stmts : Array Json) : Array String :=
  stmts.foldl (fun acc stmt =>
    let acc := appendUnique acc (stmtBoundNames stmt)
    if jsonNodeType? stmt == some "FunctionDef" then acc
    else (nestedBlocks stmt).foldl (fun a block => appendUnique a (bodyBoundNames block)) acc) #[]

/-- The declared parameter names of a `FunctionDef`, in order. -/
def functionParamNames (fnJson : Json) : Array String := Id.run do
  let .ok args := fnJson.getObjVal? "args" | return #[]
  let .ok argsArray := args.getObjValAs? (Array Json) "args" | return #[]
  return argsArray.foldl (fun acc arg =>
    match arg.getObjValAs? String "arg" with
    | .ok name => acc.push name
    | _ => acc) #[]

/-- `param name → annotation` for a `FunctionDef`, so a lifted capture keeps its type. -/
def functionParamAnnotations (fnJson : Json) : Std.HashMap String Json := Id.run do
  let .ok args := fnJson.getObjVal? "args" | return {}
  let .ok argsArray := args.getObjValAs? (Array Json) "args" | return {}
  let mut m : Std.HashMap String Json := {}
  for arg in argsArray do
    if let .ok name := arg.getObjValAs? String "arg" then
      if let .ok annotation := arg.getObjVal? "annotation" then
        unless annotation.isNull do
          m := m.insert name annotation
  return m

/-- Python methods that mutate their receiver, so a captured container they are called on is
mutated rather than merely read. -/
private def mutatingMethodName (attr : String) : Bool :=
  #["append", "appendleft", "extend", "insert", "pop", "popleft", "remove", "clear",
    "sort", "reverse", "add", "discard", "update", "setdefault"].contains attr

/-- Root `Name` id of `x`, `x[i]`, `x.f`, `x[i].g`. -/
private partial def targetRootName (target : Json) : Option String :=
  match jsonNodeType? target with
  | some "Name" => (target.getObjValAs? String "id").toOption
  | some "Subscript" | some "Attribute" =>
      match target.getObjVal? "value" with
      | .ok inner => targetRootName inner
      | _ => none
  | _ => none

/-- Does `json` mutate `name`: rebind it, assign through it (`x[i] = v`), or call a mutating
method on it? -/
partial def jsonMutatesCapture (json : Json) (name : String) : Bool :=
  let here :=
    match jsonNodeType? json with
    | some "Assign" | some "AugAssign" | some "AnnAssign" | some "For" =>
        match json.getObjVal? "target" with
        | .ok target => targetRootName target == some name
        | _ => false
    | some "Call" =>
        match json.getObjVal? "func" with
        | .ok func =>
            jsonNodeType? func == some "Attribute" &&
              (match func.getObjValAs? String "attr" with
               | .ok attr => mutatingMethodName attr
               | _ => false) &&
              (match func.getObjVal? "value" with
               | .ok recv => targetRootName recv == some name
               | _ => false)
        | _ => false
    | _ => false
  if here then true
  else match json with
    | .arr elems => elems.any (jsonMutatesCapture · name)
    | .obj fields => fields.toList.any (fun (_, v) => jsonMutatesCapture v name)
    | _ => false

/-- A `Name` load node. -/
private def nameNode (id : String) : Json :=
  Json.mkObj [("node_type", Json.str "Name"), ("id", Json.str id)]

/-- An `arg` node, carrying `annotation` when the capture's type is known. -/
private def argNode (name : String) (annotation : Option Json) : Json :=
  Json.mkObj [("node_type", Json.str "arg"), ("arg", Json.str name),
              ("annotation", annotation.getD Json.null)]

/-- Rewrite every call `old(args…)` into `new(args…, captures…)`.

A bare reference to `old` outside call position (passing the helper as a value) would need a
partially-applied closure over the captures; reject it instead of emitting something wrong. -/
partial def rewriteHelperCalls (old new : String) (captures : Array String) (json : Json) :
    PygenM Json := do
  match json with
  | .arr elems => return Json.arr (← elems.mapM (rewriteHelperCalls old new captures))
  | .obj fields =>
      if jsonNodeType? json == some "Call" then
        if let .ok func := json.getObjVal? "func" then
          if jsonNodeType? func == some "Name" && func.getObjValAs? String "id" == .ok old then
            let args := (json.getObjValAs? (Array Json) "args").toOption.getD #[]
            let args ← args.mapM (rewriteHelperCalls old new captures)
            let args := args ++ captures.map nameNode
            let keywords ← match json.getObjVal? "keywords" with
              | .ok kw => rewriteHelperCalls old new captures kw
              | _ => pure (Json.mkObj [])
            return (json.setObjVal! "func" (nameNode new)).setObjVal! "args" (Json.arr args)
              |>.setObjVal! "keywords" keywords
      if jsonNodeType? json == some "Name" && json.getObjValAs? String "id" == .ok old then
        throwError s!"nested function '{old}' is used as a value; only direct calls are supported."
      let rewritten ← fields.toList.mapM fun (k, v) => do
        return (k, ← rewriteHelperCalls old new captures v)
      return Json.mkObj rewritten
  | _ => return json

/-- Lift one nested `FunctionDef` out of `outerJson`, returning the lifted helper and the rewritten
outer function. Assumes `innerJson` has already been closure-converted itself. -/
private def liftHelper (outerName : String) (outerJson innerJson : Json) :
    PygenM (Json × Json) := do
  let .ok innerName := innerJson.getObjValAs? String "name" | throwError
    s!"nested FunctionDef is missing a 'name': {innerJson}"
  let .ok outerBody := outerJson.getObjValAs? (Array Json) "body" | throwError
    s!"FunctionDef is missing a 'body': {outerJson}"

  -- A capture is a name the helper reads that the enclosing function binds. Intersecting with the
  -- outer scope keeps builtins (`len`, `range`) and globals out of the parameter list.
  let outerBound := appendUnique (functionParamNames outerJson) (bodyBoundNames outerBody)
  let innerBound := appendUnique (functionParamNames innerJson)
    (bodyBoundNames ((innerJson.getObjValAs? (Array Json) "body").toOption.getD #[]))
  let innerUsed := jsonNameIds innerJson
  let captures := outerBound.filter fun name =>
    innerUsed.contains name && !innerBound.contains name && name != innerName

  let mutated := captures.filter (jsonMutatesCapture innerJson ·)
  unless mutated.isEmpty do
    throwError s!"nested function '{innerName}' mutates the captured variable(s) \
      {mutated.toList}; that needs state threading, which is not supported yet."

  let helperName := s!"_{outerName}_{innerName}"
  -- References to a user function are suffixed in the `'rn` twin; the helper is a user function too.
  userNamesRef.modify (helperName :: ·)

  let annotations := functionParamAnnotations outerJson
  let .ok innerArgs := innerJson.getObjVal? "args" | throwError
    s!"nested FunctionDef is missing 'args': {innerJson}"
  let innerArgsArray := (innerArgs.getObjValAs? (Array Json) "args").toOption.getD #[]
  let extraArgs := captures.map fun c => argNode c (annotations[c]?)
  let innerArgs := innerArgs.setObjVal! "args" (Json.arr (innerArgsArray ++ extraArgs))

  -- Inside the helper the captures are now parameters, so a self-call passes them straight through.
  let innerBodyJson ← rewriteHelperCalls innerName helperName captures
    (Json.arr ((innerJson.getObjValAs? (Array Json) "body").toOption.getD #[]))
  let helper := ((innerJson.setObjVal! "name" (Json.str helperName)).setObjVal! "args" innerArgs)
    |>.setObjVal! "body" innerBodyJson

  -- The enclosing body drops the `def` and calls the helper with the captures appended.
  let remaining := outerBody.filter fun stmt =>
    !(jsonNodeType? stmt == some "FunctionDef"
      && stmt.getObjValAs? String "name" == .ok innerName)
  let rewrittenBody ← rewriteHelperCalls innerName helperName captures (Json.arr remaining)
  return (helper, outerJson.setObjVal! "body" rewrittenBody)

/-- Lift every nested `def` out of `fnJson`, innermost-first. Returns the helper functions (to be
emitted as sibling `partial def`s, before `fnJson`) and the rewritten function. -/
partial def closureConvertFunction (fnJson : Json) : PygenM (Array Json × Json) := do
  let .ok body := fnJson.getObjValAs? (Array Json) "body" | return (#[], fnJson)
  let .ok outerName := fnJson.getObjValAs? String "name" | return (#[], fnJson)
  let nested := body.filter (jsonNodeType? · == some "FunctionDef")
  if nested.isEmpty then return (#[], fnJson)

  -- A helper that calls a sibling would have to capture whatever that sibling captures (a fixpoint),
  -- and mutually recursive siblings would need a `mutual` block. Reject rather than mis-compile.
  let nestedNames := nested.filterMap (·.getObjValAs? String "name" |>.toOption)
  for innerJson in nested do
    let .ok innerName := innerJson.getObjValAs? String "name" | pure ()
    let used := jsonNameIds innerJson
    if let some sibling := nestedNames.find? (fun n => n != innerName && used.contains n) then
      throwError s!"nested function '{innerName}' calls its sibling '{sibling}'; helpers that \
        reference each other are not supported yet."

  let mut helpers := #[]
  let mut current := fnJson
  for innerJson in nested do
    -- Outermost-first: lift `inner` here, so the names it captures from *this* scope become its
    -- parameters. Only then convert its own nested defs, which can now capture those parameters —
    -- `def a: def b: def c` where `c` reads a variable of `a` only works in this order.
    let (helper, rewritten) ← liftHelper outerName current innerJson
    let (subHelpers, helper) ← closureConvertFunction helper
    helpers := (helpers ++ subHelpers).push helper
    current := rewritten
  return (helpers, current)

end PastaLean
