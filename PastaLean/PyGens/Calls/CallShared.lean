import Mathlib
import PastaLean.Codegen
import PastaLean.PyGens.Basic
import PastaLean.PyGens.Core.Utils
import TypeInfer

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-- Keyword-argument object in Python call JSON. -/
abbrev PyKeywordArgs := Std.TreeMap.Raw String Json compare

/-- The Lean type of a `PyType`, with `float` resolved against the current numeric mode. -/
def pyTypeSyntax? (t : TypeInfer.PyType) : PygenM (Option (TSyntax `term)) := do
  let floatTy : TSyntax `term ← match ← getNumericMode with
    | .exact => pure (mkIdent (if (← getRealContext) then ``Real else ``Rat))
    | .approx => pure (mkIdent ``Float)
  TypeInfer.toTypeSyntax? floatTy t

/-- The Lean type stamped on a node by the inference pass (`_ty`), if any. `_ty` is an annotation
node, so it round-trips through `PyType` and the full emitter — covering lists, dicts, tuples and
`Optional`, not just the shapes the annotation reader handles directly. -/
def stampedTypeSyntax? (node : Json) : PygenM (Option (TSyntax `term)) := do
  match jsonFieldOption node "_ty" with
  | some ann => pyTypeSyntax? (TypeInfer.ofAnnotation ann)
  | none => return none

/-- Infer a simple runtime type from a value expression when the shape is obvious. -/
def inferSimpleValueTypeSyntax? (json : Json) : PygenM (Option (TSyntax `term)) :=
  pyTypeSyntax? (TypeInfer.ofValue json)

/-- Infer a simple iterable element type from obvious literal iterables. -/
def inferIterableElemTypeSyntax? (json : Json) : PygenM (Option (TSyntax `term)) := do
  -- Iterating a `String` yields `Char`, not a one-character `String`.
  match TypeInfer.ofValue json with
  | .str => return some (mkIdent ``Char)
  | t => pyTypeSyntax? t.elemType

/-- Read the positional parameter names from a lambda node without depending on `FuncDef.lean`. -/
def lambdaArgIdents (json : Json) : PygenM (Array (TSyntax `ident)) := do
  let .ok argsJson := json.getObjValAs? Json "args" | throwError
    s!"Lambda node does not have an 'args' field or it is not a JSON value: {json}"
  let .ok argsArray := argsJson.getObjValAs? (Array Json) "args" | throwError
    s!"Lambda args does not have an 'args' field or it is not a JSON array: {argsJson}"
  argsArray.mapM fun argJson => do
    let .ok argName := argJson.getObjValAs? String "arg" | throwError
      s!"Lambda argument does not have an 'arg' field or it is not a string: {argJson}"
    pure (mkIdent argName.toName)

/--
Stamp a binary lambda with either concrete runtime types or `_` placeholders so overloaded
operators inside higher-order calls elaborate more predictably.
-/
def typedBinaryLambdaCode (funcJson : Json) (fallback : TSyntax `term)
    (paramTy? : Option (TSyntax `term)) : PygenM (TSyntax `term) := do
  unless funcJson.getObjValAs? String "node_type" == .ok "Lambda" do
    return fallback
  let argIdents ← lambdaArgIdents funcJson
  unless argIdents.size == 2 do
    return fallback
  let .ok bodyJson := funcJson.getObjValAs? Json "body" | throwError
    s!"Lambda node does not have a 'body' field or it is not a JSON value: {funcJson}"
  let bodyStx ← getCode bodyJson `term
  let arg0 := argIdents[0]!
  let arg1 := argIdents[1]!
  let paramTy ← match paramTy? with
    | some stx => pure stx
    | none => `(_)
  `(fun ($arg0 : $paramTy) ↦ fun ($arg1 : $paramTy) ↦ $bodyStx)

/-- Methods that both return a value and mutate the receiver, mapped to the runtime pair
`(value, rest)` implementing them. `pop` also accepts an optional index; `popleft` takes none. -/
def valueAndMutateMethod? (attr : String) : Option (Lean.Name × Lean.Name × Bool) :=
  match attr with
  | "pop"     => some (``PastaLean.pyPopValue, ``PastaLean.pyPopRest, true)   -- optional index
  | "popleft" => some (``PastaLean.pyPopLeftValue, ``PastaLean.pyPopLeftRest, false)
  | _         => none

/-- Recognize `container.<m>(idx?)` for a value-and-mutate method `m` on an already-declared
mutable variable. Returns the method's runtime pair, the container ident, and the optional index.
A freshly-seen receiver is not a mutation site, so it returns `none`. -/
def popCallParts? (value : Json) :
    PygenM (Option ((Lean.Name × Lean.Name) × TSyntax `ident × Option (TSyntax `term))) := do
  unless jsonNodeType? value == some "Call" do return none
  let .ok funcJson := value.getObjVal? "func" | return none
  unless jsonNodeType? funcJson == some "Attribute" do return none
  let .ok attr := funcJson.getObjValAs? String "attr" | return none
  let some (valueFn, restFn, takesIndex) := valueAndMutateMethod? attr | return none
  let .ok receiverJson := funcJson.getObjVal? "value" | return none
  unless jsonNodeType? receiverJson == some "Name" do return none
  let receiverIdent ← getCode receiverJson `ident
  unless (← hasVar receiverIdent.getId) do return none
  let args := (value.getObjValAs? (Array Json) "args").toOption.getD #[]
  match args.size with
  | 0 => return some ((valueFn, restFn), receiverIdent, none)
  | 1 => if takesIndex
         then return some ((valueFn, restFn), receiverIdent, some (← getCode args[0]! `term))
         else return none
  | _ => return none

/-- Lower a call that both mutates its receiver and yields a value into a `(value, update)`
pair. They each read the *original* container, so the caller binds `value` first, then runs
`update`. Covers `container.pop(idx?)` and `deque.popleft()`. -/
def mutatingCallRhsLowering? (value : Json) :
    PygenM (Option (TSyntax `term × TSyntax `doElem)) := do
  match ← popCallParts? value with
  | none =>
      -- A library member that both mutates its first arg and returns a value (`x = heapq.heappop(h)`),
      -- read from the `Libraries` mutator spec so no library names live in codegen.
      match (value.getObjVal? "func").toOption.bind libraryMutatorOf? |>.bind (·.valueRest?) with
      | some (valFn, restFn) =>
          match value.getObjValAs? (Array Json) "args" with
          | .ok args =>
              if args.size ≥ 1 && jsonNodeType? args[0]! == some "Name" then
                let recvIdent ← getCode args[0]! `ident
                let argsCodes ← args.mapM (getCode · `term)
                let valueTerm ← `($(mkIdent valFn) $argsCodes*)
                let update ← `(doElem| $recvIdent:ident := $(mkIdent restFn) $argsCodes*)
                return some (valueTerm, update)
              else return none
          | _ => return none
      | none => return none
  | some ((valueFn, restFn), receiverIdent, index?) =>
      let valueIdent := mkIdent valueFn
      let restIdent := mkIdent restFn
      let valueTerm ← match index? with
        | none => `($valueIdent $receiverIdent)
        | some idx => `($valueIdent $receiverIdent $idx)
      let update ← match index? with
        | none => `(doElem| $receiverIdent:ident := $restIdent $receiverIdent)
        | some idx => `(doElem| $receiverIdent:ident := $restIdent $receiverIdent $idx)
      return some (valueTerm, update)

end PastaLean
