import Mathlib
import PyAstLean.Codegen
import PyAstLean.ConstantGen
open Lean Meta Elab Term Qq Std

namespace PyAstLean

@[pygen "Call"]
def callSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
  | `term, json => do
    let .ok funcJson := json.getObjValAs? Json "func" | throwError
      s!"Call node does not have a 'func' field or it is not a JSON value: {json}"
    let .ok argsJson := json.getObjValAs? Json "args" | throwError
      s!"Call node does not have an 'args' field or it is not a JSON value: {json}"
    let funcCode ← getCode funcJson `term
    let mut t ← `($funcCode)
    let argsCodes ← match argsJson with
      | .arr arr => arr.mapM (fun argJson => getCode argJson `term)
      | _ => throwError s!"Call node 'args' field is not an array: {argsJson}"
    for argCode in argsCodes do
      t ←  `($t $argCode)
    let .ok keyWordsJson := json.getObjValAs? (List (Name × Json)) "keywords" | throwError
      s!"Call node does not have a 'keywords' field or it is not json pairs: {json}"
    for (kwName, kwValueJson) in keyWordsJson do
      let kwValueCode ← getCode kwValueJson `term
      let kwId := mkIdent kwName
      t ← `($t ($kwId:ident := $kwValueCode))
    return t
  | _, _ => throwError s!"Unsupported syntax category for Call node"
