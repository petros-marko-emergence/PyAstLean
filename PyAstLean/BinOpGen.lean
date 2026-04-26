import Mathlib
import PyAstLean.Codegen
import PyAstLean.ConstantGen
open Lean Meta Elab Term Qq Std

namespace PyAstLean


class PyHAdd (α β : Type) (γ : outParam Type) where
  hAdd : α → β → γ

infix:65 " (+) " => PyHAdd.hAdd

instance {α β γ} [HAdd α β γ] : PyHAdd α β γ where
  hAdd := HAdd.hAdd

instance : PyHAdd String String String where
  hAdd := String.append

#eval 1 (+) 2
#eval "Hello, " (+) "World!"

@[pygen "BinOp"]
def binOpSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
  | `term, json => do
    let .ok op := json.getObjValAs? String "op" | throwError
      s!"BinOp node does not have an 'op' field or it is not a string: {json}"
    let .ok leftJson := json.getObjValAs? Json "left" | throwError
      s!"BinOp node does not have a 'left' field or it is not a JSON value: {json}"
    let .ok rightJson := json.getObjValAs? Json "right" | throwError
      s!"BinOp node does not have a 'right' field or it is not a JSON value: {json}"
    let leftCode ←  getCode leftJson `term
    let rightCode ← getCode rightJson `term
    match op with
    | "add" => `($leftCode (+) $rightCode)
    | _ => throwError s!"Unsupported binary operator: {op}"
  | _, _ => throwError s!"Unsupported syntax category for BinOp node"

-- Example
def onePlusTwoNode := json% {
    "node_type": "BinOp",
    "op": "add",
    "left": {
      "node_type": "Constant",
      "value": 1
    },
    "right": {
      "node_type": "Constant",
      "value": 2
    }
  }

#eval py_term% onePlusTwoNode
#eval onePlusTwoNode.compress


-- #eval getCodeTerm (json% {
--     "node_type": "BinOp",
--     "op": "add",
--     "left": {
--       "node_type": "Constant",
--       "value": "Hello"
--     },
--     "right": {
--       "node_type": "Constant",
--       "value": 2
--     }
--   })

end PyAstLean
