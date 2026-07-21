import Libraries.collections.CollectionsDef
import PastaLean.PyGens.Calls.CallEffects
import PastaLean.PyGens.Calls.CallShared

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-- The `collections` member this call targets, if any: `Counter(...)` / `defaultdict(...)`. -/
def collectionsMember? (json : Json) : Option String :=
  match json.getObjValAs? String "library_module", json.getObjValAs? String "library_member" with
  | .ok "collections", .ok member => some member
  | _, _ =>
      if json.getObjValAs? String "node_type" == .ok "Attribute"
         && (json.getObjValAs? Json "value").toOption.any (fun v =>
              v.getObjValAs? String "node_type" == .ok "Name"
              && v.getObjValAs? String "id" == .ok "collections") then
        (json.getObjValAs? String "attr").toOption
      else none

/-- The bare name of a `defaultdict` factory argument: `defaultdict(list)` ↦ `"list"`. -/
private def factoryName? (argJson : Json) : Option String :=
  if argJson.getObjValAs? String "node_type" == .ok "Name" then
    (argJson.getObjValAs? String "id").toOption
  else none

/-- Lower `Counter()` / `Counter(xs)` / `defaultdict(list)` / `defaultdict(int)`. -/
def lowerCollectionsCallTerm? (funcJson : Json) (argsArray : Array Json)
    (argsCodes : Array (TSyntax `term)) (keyWordsMap : PyKeywordArgs) :
    PygenM (Option (TSyntax `term)) := do
  let some member := collectionsMember? funcJson | return none
  match member with
  | "Counter" =>
      unless keyWordsMap.isEmpty do
        throwError "Counter() keyword arguments are not supported yet."
      match argsArray.size with
      | 0 => return some (← `($(mkIdent ``Libraries.collections.pyCounterEmpty)))
      | 1 =>
          let counterIdent := mkIdent ``Libraries.collections.pyCounter
          return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r => do
            `($counterIdent $(r[0]!)))
      | _ => throwError "Counter() expects at most one positional argument."
  | "defaultdict" =>
      unless keyWordsMap.isEmpty do
        throwError "defaultdict() keyword arguments are not supported yet."
      let some argJson := argsArray[0]?
        | throwError "defaultdict() expects a default-factory argument, e.g. `defaultdict(list)`."
      match factoryName? argJson with
      -- Sets are `List`-backed in the runtime, so `set` shares the empty-list default.
      | some "list" | some "set" =>
          return some (← `($(mkIdent ``Libraries.collections.pyDefaultDictList)))
      | some "int"  => return some (← `($(mkIdent ``Libraries.collections.pyDefaultDictInt)))
      | other =>
          throwError s!"defaultdict({other.getD "?"}) is not supported; only `list`, `set` and \
            `int` default factories are."
  | "deque" =>
      unless keyWordsMap.isEmpty do
        throwError "deque() keyword arguments are not supported yet."
      match argsArray.size with
      | 0 => return some (← `($(mkIdent ``Libraries.collections.pyDequeEmpty)))
      | 1 =>
          let dequeIdent := mkIdent ``Libraries.collections.pyDeque
          return some (← buildIOPureApplicationFromArgs argsArray argsCodes fun r => do
            `($dequeIdent $(r[0]!)))
      | _ => throwError "deque() expects at most one positional argument."
  | _ => return none

end PastaLean
