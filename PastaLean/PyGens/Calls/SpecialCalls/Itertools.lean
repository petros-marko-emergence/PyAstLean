import Libraries.itertools.ItertoolsDef
import PastaLean.PyGens.Calls.CallEffects
import PastaLean.PyGens.Calls.CallShared

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-- The `itertools` member name for a call whose func is an imported itertools member. -/
def itertoolsMember? (json : Json) : Option String :=
  match json.getObjValAs? String "library_module", json.getObjValAs? String "library_member" with
  | .ok "itertools", .ok m => some m
  | _, _ => none

/-- Stamp a unary lambda with a concrete param type so its body's operators (`x < 5`) elaborate. -/
def typedUnaryLambdaCode (funcJson : Json) (fallback : TSyntax `term)
    (paramTy? : Option (TSyntax `term)) : PygenM (TSyntax `term) := do
  unless funcJson.getObjValAs? String "node_type" == .ok "Lambda" do return fallback
  let argIdents ← lambdaArgIdents funcJson
  unless argIdents.size == 1 do return fallback
  let .ok bodyJson := funcJson.getObjValAs? Json "body" | return fallback
  let bodyStx ← getCode bodyJson `term
  let paramTy ← match paramTy? with | some stx => pure stx | none => `(_)
  `(fun ($(argIdents[0]!) : $paramTy) ↦ $bodyStx)

/-- Custom term lowering for `itertools` calls that the generic library path can't build:
variadic members (wrap the args into a list), predicate/function members (type the lambda), and
`accumulate(initial=…)` (wrap the initial in `some`). Returns `none` to fall through to the generic
path (e.g. `accumulate` with no `initial`, handled via the member map). -/
def lowerItertoolsCallTerm? (funcJson : Json) (argsArray : Array Json) (argsCodes : Array (TSyntax `term))
    (keyWordsMap : PyKeywordArgs) : PygenM (Option (TSyntax `term)) := do
  let some member := itertoolsMember? funcJson | return none
  match member with
  -- Variadic: `chain(a, b, …)` / `product(a, b, …)` → `pyX [a, b, …]`.
  | "chain" =>
      let ident := mkIdent ``Libraries.itertools.pyChain
      return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r => `($ident [$r,*]))
  | "product" =>
      let ident := mkIdent ``Libraries.itertools.pyProduct
      return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r => `($ident [$r,*]))
  -- `chain.from_iterable(xss)`: `xss` is already the list of iterables.
  | "from_iterable" =>
      let ident := mkIdent ``Libraries.itertools.pyChain
      if argsCodes.size == 1 then
        return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r => `($ident $(r[0]!)))
      else return none
  -- `zip_longest(a, b, fillvalue=f)`: two same-type iterables padded with `f`.
  | "zip_longest" =>
      match keyWordsMap.get? "fillvalue", argsArray.size with
      | some fillJson, 2 =>
          let fillCode ← getCode fillJson `term
          let ident := mkIdent ``Libraries.itertools.pyZipLongest
          return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r =>
            `($ident $fillCode $(r[0]!) $(r[1]!)))
      | _, _ => return none
  -- Predicate members: type the unary lambda against the sequence's element type.
  | "dropwhile" | "takewhile" | "filterfalse" =>
      if argsArray.size != 2 then return none
      let ident := mkIdent (match member with
        | "dropwhile" => ``Libraries.itertools.pyDropwhile
        | "takewhile" => ``Libraries.itertools.pyTakewhile
        | _ => ``Libraries.itertools.pyFilterfalse)
      let elemTy? ← inferIterableElemTypeSyntax? argsArray[1]!
      let predCode ← typedUnaryLambdaCode argsArray[0]! argsCodes[0]! elemTy?
      return some (← buildIOPureApplicationFromArgs argsArray #[predCode, argsCodes[1]!] fun r =>
        `($ident $(r[0]!) $(r[1]!)))
  -- `starmap(f, xs)`: type the binary lambda; `xs` is a list of pairs.
  | "starmap" =>
      if argsArray.size != 2 then return none
      let ident := mkIdent ``Libraries.itertools.pyStarmap
      let funcCode ← typedBinaryLambdaCode argsArray[0]! argsCodes[0]! none
      return some (← buildIOPureApplicationFromArgs argsArray #[funcCode, argsCodes[1]!] fun r =>
        `($ident $(r[0]!) $(r[1]!)))
  -- `accumulate(xs, initial=v)` → `pyAccumulate xs (some v)`; without `initial`, fall through.
  | "accumulate" =>
      match keyWordsMap.get? "initial" with
      | some initJson =>
          let initCode ← getCode initJson `term
          let ident := mkIdent ``Libraries.itertools.pyAccumulate
          return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r =>
            `($ident $(r[0]!) (some $initCode)))
      | none => return none
  | _ => return none

/-- `doElem` wrapper for the itertools custom lowering. -/
def lowerItertoolsCallDoElem? (funcJson : Json) (argsArray : Array Json) (argsCodes : Array (TSyntax `term))
    (keyWordsMap : PyKeywordArgs) : PygenM (Option (TSyntax `doElem)) := do
  match ← lowerItertoolsCallTerm? funcJson argsArray argsCodes keyWordsMap with
  | some t =>
      if argsArray.toList.any basicJsonUsesMonadicEffect then
        return some (← `(doElem| let _ ← $t:term))
      else
        return some (← `(doElem| let _ := $t))
  | none => return none

end PastaLean
