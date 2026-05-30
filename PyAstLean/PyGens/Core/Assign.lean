import PyAstLean.PyGens.Core.Utils
import PyAstLean.PyGens.Calls.CallEffects

open Lean Meta Elab Term Qq Std

namespace PyAstLean

/-- Read a simple two-name tuple assignment target when present. -/
def tupleAssignTargetNames? (target : Json) : PygenM (Option (TSyntax `ident × TSyntax `ident)) := do
  unless jsonNodeType? target == some "Tuple" do
    return none
  let .ok elts := target.getObjValAs? (Array Json) "elts" | throwError
    s!"Tuple assignment target does not have an 'elts' field or it is not a JSON value: {target}"
  match elts[0]?, elts[1]? with
  | some leftJson, some rightJson =>
      if jsonNodeType? leftJson == some "Name" && jsonNodeType? rightJson == some "Name" then
        let leftIdent ← getCode leftJson `ident
        let rightIdent ← getCode rightJson `ident
        return some (leftIdent, rightIdent)
      else
        throwError "Only two-name tuple assignment targets are supported right now."
  | _, _ =>
      throwError "Only two-element tuple assignment targets are supported right now."

/-- Emit either a fresh `let mut` or a reassignment for one local binding. -/
def bindOrAssignLocal (nameIdent : TSyntax `ident) (rhs : TSyntax `term) : PygenM (TSyntax `doElem) := do
  if ← hasVar nameIdent.getId then
    `(doElem| $nameIdent:ident := $rhs)
  else
    let stx ← `(doElem| let mut $nameIdent:ident := $rhs)
    addVar nameIdent.getId
    pure stx

/-- Normalize Python-style two-target unpacking through the iterable protocol. -/
def unpack2Term (value : TSyntax `term) : PygenM (TSyntax `term) := do
  let pyUnpack2Ident := mkIdent ``PyAstLean.pyUnpack2
  `($pyUnpack2Ident $value)

/-- Simple returned expressions can stay unparenthesized; more complex or effectful ones
keep parentheses so Lean parses multiline `return` expressions reliably. -/
def shouldParenthesizeReturnValue (value : Json) : Bool :=
  if jsonUsesMonadicEffect value then
    true
  else
    match jsonNodeType? value with
    | some "Name" => false
    | some "Constant" => false
    | some "Attribute" => false
    | _ => true

@[pygen "Assign"]
def assignSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
    | `command, json => do
        let .ok target := json.getObjVal? "target" | throwError
          s!"Assign node does not have a 'target' field or it is not a JSON value: {json}"
        let .ok value := json.getObjVal? "value" | throwError
          s!"Assign node does not have a 'value' field or it is not a JSON value: {json}"
        match ← tupleAssignTargetNames? target with
        | some (leftIdent, rightIdent) => do
            let valueStx ← getCode value `term
            let unpackTmpName := Name.mkSimple s!"__py_unpack_{leftIdent.getId.toString}_{rightIdent.getId.toString}"
            let unpackTmpIdent := mkIdent unpackTmpName
            let unpackedValue ← unpack2Term valueStx
            let fstIdent := mkIdent ``Prod.fst
            let sndIdent := mkIdent ``Prod.snd
            let cmd1 ← `(command| def $unpackTmpIdent := $unpackedValue)
            let cmd2 ← `(command| def $leftIdent := $fstIdent $unpackTmpIdent)
            let cmd3 ← `(command| def $rightIdent := $sndIdent $unpackTmpIdent)
            pure ⟨mkNullNode #[cmd1.raw, cmd2.raw, cmd3.raw]⟩
        | none => do
            let nameIdent ← getCode target `ident
            let valueStx ← getCode value `term
            `(def $nameIdent := $valueStx)
    | `doElem, json => do
        let .ok target := json.getObjVal? "target" | throwError
          s!"Assign node does not have a 'target' field or it is not a JSON value: {json}"
        let .ok value := json.getObjVal? "value" | throwError
          s!"Assign node does not have a 'value' field or it is not a JSON value: {json}"
        match ← tupleAssignTargetNames? target with
        | some (leftIdent, rightIdent) => do
            let valueStx ← getCode value `term
            let valueTmpIdent := mkIdent (← freshName `__unpack_value)
            let unpackTmpIdent := mkIdent (← freshName `__unpack_pair)
            let bindValueTmp ←
              if jsonUsesIOEffect value || jsonUsesMonadicEffect value then
                `(doElem| let $valueTmpIdent:ident ← $valueStx:term)
              else
                `(doElem| let $valueTmpIdent:ident := $valueStx)
            let unpackedValue ← unpack2Term valueTmpIdent
            let bindUnpackTmp ← `(doElem| let $unpackTmpIdent:ident := $unpackedValue)
            let leftBind ← bindOrAssignLocal leftIdent (← `(Prod.fst $unpackTmpIdent))
            let rightBind ← bindOrAssignLocal rightIdent (← `(Prod.snd $unpackTmpIdent))
            `(doElem| do
              $bindValueTmp:doElem
              $bindUnpackTmp:doElem
              $leftBind:doElem
              $rightBind:doElem)
        | none => do
            let nameIdent ← getCode target `ident
            let rhs ←
              if jsonUsesIOEffect value then
                inlineIOTerm value
              else
                let valueStx ← getCode value `term
                if jsonUsesMonadicEffect value then
                  `((← $valueStx))
                else
                  pure valueStx
            bindOrAssignLocal nameIdent rhs
    | _, _ => throwError s!"Unsupported syntax category for Assign node"

/--
`AnnAssign` represents Python's annotated assignment syntax (`x : T = v` or `x : T`).
The remaining declaration-only form is currently treated as a no-op in `do` blocks, and
rejected at top level until the backend grows explicit type-directed declarations.
-/
@[pygen "AnnAssign"]
def annAssignSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
    | `command, json => do
        let .ok value? := json.getObjVal? "value" | throwError
          s!"AnnAssign node does not have a 'value' field or it is not a JSON value: {json}"
        match value? with
        | .null =>
            throwError "Declaration-only annotated assignments are not yet supported at top level."
        | _ =>
            let targetJson := Json.mkObj [("node_type", Json.str "Assign")]
            let json := targetJson.mergeObj json
            assignSyntax `command json
    | `doElem, json => do
        let .ok value? := json.getObjVal? "value" | throwError
          s!"AnnAssign node does not have a 'value' field or it is not a JSON value: {json}"
        match value? with
        | .null =>
            `(doElem| let _ := ())
        | _ =>
            let targetJson := Json.mkObj [("node_type", Json.str "Assign")]
            let json := targetJson.mergeObj json
            assignSyntax `doElem json
    | _, _ => throwError s!"Unsupported syntax category for AnnAssign node"

@[pygen "Return"]
def returnSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
    | `doElem, json => do
        let .ok value := json.getObjVal? "value" | throwError
          s!"Return node does not have a 'value' field or it is not a JSON value: {json}"
        match value with
        | .null =>
            `(doElem| return (()))
        | _ =>
            if jsonUsesIOEffect value then
              let valueStx ← inlineIOTerm value
              if shouldParenthesizeReturnValue value then
                `(doElem| return ($valueStx))
              else
                `(doElem| return $valueStx)
            else
              let valueStx ← getCode value `term
              if jsonUsesMonadicEffect value then
                `(doElem| return (← $valueStx:term))
              else
                if shouldParenthesizeReturnValue value then
                  `(doElem| return ($valueStx))
                else
                  `(doElem| return $valueStx)
    | _, _ => throwError s!"Unsupported syntax category for Return node"

end PyAstLean
