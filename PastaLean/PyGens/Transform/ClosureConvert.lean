import PastaLean.PyGens.Core.Utils
import TypeInfer

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

/-- Annotations inferred for the enclosing function's locals, from their first assignment. Without
these a lifted capture is an untyped parameter and Lean's instance resolution gets stuck. -/
partial def localAnnotations (stmts : Array Json) : Std.HashMap String Json :=
  stmts.foldl (init := {}) fun acc stmt =>
    let acc :=
      if jsonNodeType? stmt == some "Assign" then
        match stmt.getObjVal? "target", stmt.getObjVal? "value" with
        | .ok target, .ok value =>
            -- Prefer the inference pass's `_ty` (mutation-informed); fall back to the RHS shape.
            let annotation? := (jsonFieldOption target "_ty").orElse fun _ =>
              TypeInfer.toAnnotation? (TypeInfer.ofValue value)
            match target.getObjValAs? String "id", annotation? with
            | .ok name, some annotation =>
                if acc.contains name then acc else acc.insert name annotation
            | _, _ => acc
        | _, _ => acc
      else acc
    if jsonNodeType? stmt == some "FunctionDef" then acc
    else (nestedBlocks stmt).foldl (fun a block =>
      (localAnnotations block).fold (fun m k v => if m.contains k then m else m.insert k v) a) acc

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
      -- `old` as a VALUE (`sort(key=old)`): a capture-free helper is a real top-level def → just `new`.
      -- A capturing one can't be a bare value (captures come after its params), so reject it.
      if jsonNodeType? json == some "Name" && json.getObjValAs? String "id" == .ok old then
        if captures.isEmpty then return nameNode new
        else throwError s!"nested function '{old}' captures variables and is used as a value; \
          only direct calls are supported."
      let rewritten ← fields.toList.mapM fun (k, v) => do
        return (k, ← rewriteHelperCalls old new captures v)
      return Json.mkObj rewritten
  | _ => return json


/-! ### State threading

A helper cannot mutate a captured variable — Lean closures are pure. So a capture it rebinds
(`nonlocal ans`) or mutates in place (`grid[i][j] = v`, `xs.append(x)`) is **threaded**: appended to
the parameter list *and* returned, with every call site rebinding it.
-/

/-- `Tuple` of `elts`, or the single element itself (so one threaded name stays a plain name). -/
private def tupleNode (elts : Array Json) : Json :=
  if elts.size == 1 then elts[0]!
  else Json.mkObj [("node_type", Json.str "Tuple"), ("elts", Json.arr elts)]

private def assignNode (target value : Json) : Json :=
  Json.mkObj [("node_type", Json.str "Assign"), ("target", target), ("value", value)]

private def returnNode (value : Option Json) : Json :=
  Json.mkObj [("node_type", Json.str "Return"), ("value", value.getD Json.null)]

/-- The `Nonlocal` names declared anywhere in `json`. -/
partial def nonlocalNames (json : Json) : Array String :=
  let here := if jsonNodeType? json == some "Nonlocal" then
      (json.getObjValAs? (Array String) "names").toOption.getD #[]
    else #[]
  match json with
  | .arr elems => elems.foldl (fun acc e => appendUnique acc (nonlocalNames e)) here
  | .obj fields => fields.toList.foldl (fun acc (_, v) => appendUnique acc (nonlocalNames v)) here
  | _ => here

/-- The statement-list fields of a node. -/
private def blockFields : Array String := #["body", "orelse", "finalbody"]

/-- Rewrite every statement list in `json` with `f`, innermost first. -/
partial def mapStatementLists (f : Array Json → Array Json) (json : Json) : Json :=
  match json with
  | .arr elems => Json.arr (elems.map (mapStatementLists f))
  | .obj fields =>
      Json.mkObj (fields.toList.map fun (key, value) =>
        let value := mapStatementLists f value
        if blockFields.contains key then
          match value with
          | .arr stmts => (key, Json.arr (f stmts))
          | _ => (key, value)
        else (key, value))
  | _ => json

/-- Drop `nonlocal` declarations; the names they refer to become threaded parameters. -/
def stripNonlocal (json : Json) : Json :=
  mapStatementLists (fun stmts => stmts.filter (jsonNodeType? · != some "Nonlocal")) json

/-- Is `json` a call to `name`? -/
private def isCallTo (name : String) (json : Json) : Bool :=
  jsonNodeType? json == some "Call" &&
    (match json.getObjVal? "func" with
     | .ok func => jsonNodeType? func == some "Name" && func.getObjValAs? String "id" == .ok name
     | _ => false)

/-- Does `json` contain a call to `name` anywhere? -/
partial def containsCallTo (name : String) (json : Json) : Bool :=
  if isCallTo name json then true
  else match json with
    | .arr elems => elems.any (containsCallTo name)
    | .obj fields => fields.toList.any (fun (_, v) => containsCallTo name v)
    | _ => false

/-- `Return` nodes carrying a value, anywhere outside a nested definition. -/
partial def hasValuedReturn (json : Json) : Bool :=
  if jsonNodeType? json == some "FunctionDef" then false
  else if jsonNodeType? json == some "Return" then
    match json.getObjVal? "value" with
    | .ok value => !value.isNull
    | _ => false
  else match json with
    | .arr elems => elems.any hasValuedReturn
    | .obj fields => fields.toList.any (fun (_, v) => hasValuedReturn v)
    | _ => false

/-- A `Return` with no value, anywhere outside a nested definition. -/
partial def hasBareReturn (json : Json) : Bool :=
  if jsonNodeType? json == some "FunctionDef" then false
  else if jsonNodeType? json == some "Return" then
    match json.getObjVal? "value" with
    | .ok value => value.isNull
    | _ => true
  else match json with
    | .arr elems => elems.any hasBareReturn
    | .obj fields => fields.toList.any (fun (_, v) => hasBareReturn v)
    | _ => false

/-- Every `return e` also yields the threaded names, and a helper that falls off the end returns
them too. -/
partial def threadReturns (threaded : Array String) (hasValue : Bool) (json : Json) : Json :=
  if jsonNodeType? json == some "FunctionDef" then json
  else if jsonNodeType? json == some "Return" then
    let threadedNodes := threaded.map nameNode
    match json.getObjVal? "value" with
    | .ok value =>
        if hasValue && !value.isNull then returnNode (tupleNode (#[value] ++ threadedNodes))
        else returnNode (tupleNode threadedNodes)
    | _ => returnNode (tupleNode threadedNodes)
  else match json with
    | .arr elems => Json.arr (elems.map (threadReturns threaded hasValue))
    | .obj fields =>
        Json.mkObj (fields.toList.map fun (k, v) => (k, threadReturns threaded hasValue v))
    | _ => json

/-- Build `new(args…, captures…)` from a call to `old`, after rewriting its arguments. -/
private def retargetCall (new : String) (captures : Array String) (call : Json)
    (rewrittenArgs : Array Json) : Json :=
  ((call.setObjVal! "func" (nameNode new)).setObjVal!
    "args" (Json.arr (rewrittenArgs ++ captures.map nameNode)))

/-- Is `old` referenced anywhere other than as the callee of a direct call? -/
partial def usedAsValue (old : String) (json : Json) : Bool :=
  match json with
  | .arr elems => elems.any (usedAsValue old)
  | .obj fields =>
      if isCallTo old json then
        fields.toList.any (fun (key, value) => key != "func" && usedAsValue old value)
      else if jsonNodeType? json == some "Name" && json.getObjValAs? String "id" == .ok old then true
      else fields.toList.any (fun (_, value) => usedAsValue old value)
  | _ => false

mutual

/-- Replace each threaded call inside an expression with a temporary, returning the assignments
that must run first. A helper with no return value cannot appear in a value position. -/
partial def hoistThreadedCalls (old new : String) (captures threaded : Array String)
    (hasValue : Bool) (counter : IO.Ref Nat) (expr : Json) : PygenM (Json × Array Json) := do
  if isCallTo old expr then
    let args := (expr.getObjValAs? (Array Json) "args").toOption.getD #[]
    let mut rewrittenArgs := #[]
    let mut prelude := #[]
    for arg in args do
      let (arg, pre) ← hoistThreadedCalls old new captures threaded hasValue counter arg
      rewrittenArgs := rewrittenArgs.push arg
      prelude := prelude ++ pre
    let call := retargetCall new captures expr rewrittenArgs
    unless hasValue do
      throwError s!"nested function '{old}' returns no value but is used as one."
    let n ← counter.modifyGet (fun n => (n, n + 1))
    let temp := s!"__thread_t{n + 1}"
    let target := tupleNode (#[nameNode temp] ++ threaded.map nameNode)
    return (nameNode temp, prelude.push (assignNode target call))
  match expr with
  | .arr elems =>
      let mut out := #[]
      let mut prelude := #[]
      for elem in elems do
        let (elem, pre) ← hoistThreadedCalls old new captures threaded hasValue counter elem
        out := out.push elem
        prelude := prelude ++ pre
      return (Json.arr out, prelude)
  | .obj fields =>
      let mut rewritten := []
      let mut prelude := #[]
      for (key, value) in fields.toList do
        let (value, pre) ← hoistThreadedCalls old new captures threaded hasValue counter value
        prelude := prelude ++ pre
        rewritten := rewritten ++ [(key, value)]
      return (Json.mkObj rewritten, prelude)
  | _ => return (expr, #[])

/-- Rewrite the calls to `old` in a statement list, rebinding the threaded names at each one. -/
partial def rewriteThreadedStmts (old new : String) (captures threaded : Array String)
    (hasValue : Bool) (counter : IO.Ref Nat) (stmts : Array Json) : PygenM (Array Json) := do
  let mut out := #[]
  for stmt in stmts do
    unless containsCallTo old stmt do
      out := out.push stmt
      continue
    if jsonNodeType? stmt == some "While" then
      if (stmt.getObjVal? "test").toOption.any (containsCallTo old) then
        throwError s!"call to '{old}' in a `while` test cannot rebind the threaded state."
    for context in ["Lambda", "ListComp", "SetComp", "DictComp", "GeneratorExp"] do
      if jsonContainsNodeType stmt [context] then
        throwError s!"call to '{old}' inside a {context} cannot rebind the threaded state."

    let threadedNodes := threaded.map nameNode
    -- `dfs(i, j)` as a statement: keep only the rebinding.
    if jsonNodeType? stmt == some "Expr" then
      if let .ok value := stmt.getObjVal? "value" then
        if isCallTo old value then
          let args := (value.getObjValAs? (Array Json) "args").toOption.getD #[]
          let call := retargetCall new captures value args
          let targets ←
            if hasValue then do
              let n ← counter.modifyGet (fun n => (n, n + 1))
              pure (#[nameNode s!"__thread_t{n + 1}"] ++ threadedNodes)
            else pure threadedNodes
          out := out.push (assignNode (tupleNode targets) call)
          continue
    -- `x = dfs(i, j)`: bind the value and the threaded names together.
    if jsonNodeType? stmt == some "Assign" then
      if let .ok value := stmt.getObjVal? "value" then
        if isCallTo old value then
          unless hasValue do
            throwError s!"nested function '{old}' returns no value but its result is assigned."
          let .ok target := stmt.getObjVal? "target" | throwError "Assign is missing a 'target'"
          let args := (value.getObjValAs? (Array Json) "args").toOption.getD #[]
          let call := retargetCall new captures value args
          out := out.push (assignNode (tupleNode (#[target] ++ threadedNodes)) call)
          continue

    -- Anywhere else the call sits inside an expression: hoist it to a temporary first.
    let mut stmt := stmt
    let mut prelude := #[]
    for (key, value) in (stmt.getObj?.toOption.getD ∅).toList do
      unless blockFields.contains key || key == "handlers" do
        if containsCallTo old value then
          let (value, pre) ← hoistThreadedCalls old new captures threaded hasValue counter value
          prelude := prelude ++ pre
          stmt := stmt.setObjVal! key value
    for key in blockFields do
      if let .ok block := stmt.getObjValAs? (Array Json) key then
        let block ← rewriteThreadedStmts old new captures threaded hasValue counter block
        stmt := stmt.setObjVal! key (Json.arr block)
    out := out ++ prelude
    out := out.push stmt
  return out

end

/-- Lift one nested `FunctionDef` out of `outerJson`, returning the lifted helper and the rewritten
outer function.

Captures the helper only reads become extra parameters. Captures it rebinds (`nonlocal`) or mutates
in place are **threaded**: extra parameters that the helper also returns, with each call site
rebinding them. -/
private def liftHelper (outerName : String) (outerJson innerJson : Json) :
    PygenM (Json × Json) := do
  let .ok innerName := innerJson.getObjValAs? String "name" | throwError
    s!"nested FunctionDef is missing a 'name': {innerJson}"
  let .ok outerBody := outerJson.getObjValAs? (Array Json) "body" | throwError
    s!"FunctionDef is missing a 'body': {outerJson}"

  let declaredNonlocal := nonlocalNames innerJson
  let inner := stripNonlocal innerJson
  let innerBody := (inner.getObjValAs? (Array Json) "body").toOption.getD #[]

  -- A capture is a name the helper reads that the enclosing function binds. Intersecting with the
  -- outer scope keeps builtins (`len`, `range`) and globals out of the parameter list. A `nonlocal`
  -- name is rebound inside the helper, so it looks local — add it back explicitly.
  let outerBound := appendUnique (functionParamNames outerJson) (bodyBoundNames outerBody)
  let innerBound := appendUnique (functionParamNames inner) (bodyBoundNames innerBody)
  let innerUsed := jsonNameIds inner
  let captures := outerBound.filter fun name =>
    name != innerName &&
      ((innerUsed.contains name && !innerBound.contains name) || declaredNonlocal.contains name)

  let threaded := captures.filter fun c => declaredNonlocal.contains c || jsonMutatesCapture inner c
  let readOnly := captures.filter fun c => !threaded.contains c
  let ordered := readOnly ++ threaded

  -- A capture-free helper used as a value (`sort(key=f)`) is fine — lifted to a plain reference. A
  -- capturing one can't be (captures come after its params), so reject that case.
  if (usedAsValue innerName inner || usedAsValue innerName (Json.arr outerBody)) && !captures.isEmpty then
    throwError s!"nested function '{innerName}' captures variables and is used as a value; unsupported."

  let hasValue := hasValuedReturn (Json.arr innerBody)
  unless threaded.isEmpty do
    -- A helper that sometimes returns a value and sometimes falls through would have to return an
    -- `Option`, which its callers do not expect.
    if hasValue && hasBareReturn (Json.arr innerBody) then
      throwError s!"nested function '{innerName}' mixes `return <value>` with a bare `return`; \
        threading its state would need an `Option` result."
    if hasValue && !statementListDefinitelyReturns innerBody.toList then
      throwError s!"nested function '{innerName}' can fall off the end while threading state; \
        give it an explicit `return`."

  let helperName := s!"_{outerName}_{innerName}"
  -- References to a user function are suffixed in the `'rn` twin; the helper is a user function too.
  userNamesRef.modify (helperName :: ·)

  -- Parameter annotations win; a local's type is inferred from its first assignment.
  let annotations := (localAnnotations outerBody).fold
    (fun m k v => if m.contains k then m else m.insert k v) (functionParamAnnotations outerJson)
  let .ok innerArgs := inner.getObjVal? "args" | throwError
    s!"nested FunctionDef is missing 'args': {inner}"
  let innerArgsArray := (innerArgs.getObjValAs? (Array Json) "args").toOption.getD #[]
  let extraArgs := ordered.map fun c => argNode c (annotations[c]?)
  let innerArgs := innerArgs.setObjVal! "args" (Json.arr (innerArgsArray ++ extraArgs))

  let remaining := outerBody.filter fun stmt =>
    !(jsonNodeType? stmt == some "FunctionDef"
      && stmt.getObjValAs? String "name" == .ok innerName)

  let counter ← IO.mkRef 0
  let (helperBody, rewrittenOuter) ←
    if threaded.isEmpty then do
      let body ← rewriteHelperCalls innerName helperName ordered (Json.arr innerBody)
      let outer ← rewriteHelperCalls innerName helperName ordered (Json.arr remaining)
      pure (body, outer)
    else do
      let body ← rewriteThreadedStmts innerName helperName ordered threaded hasValue counter innerBody
      let body := threadReturns threaded hasValue (Json.arr body)
      -- A helper that returns nothing still has to hand the threaded state back on every path.
      let body := match body with
        | .arr stmts =>
            if statementListDefinitelyReturns stmts.toList then Json.arr stmts
            else Json.arr (stmts.push (returnNode (tupleNode (threaded.map nameNode))))
        | other => other
      let outer ← rewriteThreadedStmts innerName helperName ordered threaded hasValue counter remaining
      pure (body, Json.arr outer)

  let helper := ((inner.setObjVal! "name" (Json.str helperName)).setObjVal! "args" innerArgs)
    |>.setObjVal! "body" helperBody
  -- Threading changes the result into a tuple, so the declared return annotation no longer holds.
  let helper := if threaded.isEmpty then helper else helper.setObjVal! "returns" Json.null
  return (helper, outerJson.setObjVal! "body" rewrittenOuter)

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
