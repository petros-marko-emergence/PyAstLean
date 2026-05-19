import PyAstLean.PyAPI.Core
import PyAstLean.PyGens.Basic

namespace PyAstLean

open Lean Elab Term Meta
open PyAstLean

@[pygen "Subscript"]
def subscriptSyntax : (kind : SyntaxNodeKind) → Json →
    PygenM (TSyntax kind)
  | `term, json => do
    let .ok valueJson := json.getObjValAs? Json "value" | throwError
      s!"Subscript node does not have a 'value' field or it is not a JSON value: {json}"
    let .ok sliceJson := json.getObjValAs? Json "slice" | throwError
      s!"Subscript node does not have a 'slice' field or it is not a JSON value: {json}"
    let valueCode ← getCode valueJson `term
    
    let isTuple := match valueJson.getObjValAs? String "node_type" with
    | .ok "Tuple" => true
    | _ => false
    
    if isTuple then
        match sliceJson.getObjValAs? String "node_type", sliceJson.getObjValAs? Json "value" with
        | .ok "Constant", .ok (.num (JsonNumber.mk 0 0)) =>
            let fstIdent := mkIdent ``Prod.fst
            `($fstIdent $valueCode)
        | .ok "Constant", .ok (.num (JsonNumber.mk 1 0)) =>
            let sndIdent := mkIdent ``Prod.snd
            `($sndIdent $valueCode)
        | _, _ =>
            let sliceCode ← getCode sliceJson `term
            let getIdent := mkIdent `getElem!
            `($getIdent $valueCode $sliceCode)
    else
        let sliceType := sliceJson.getObjValAs? String "node_type"
        match sliceType with
        | .ok "Constant" =>
            let idx := sliceJson.getObjValAs? Int "value"
            match idx with
            | .ok i =>
                let getIdent := mkIdent `PyAstLean.pyListGetItem
                let iStx ← intToStx i
                `($getIdent $valueCode $iStx)
            | _ =>
                let sliceCode ← getCode sliceJson `term
                let getIdent := mkIdent `getElem!
                `($getIdent $valueCode $sliceCode)
        | .ok "UnaryOp" =>
            let op := sliceJson.getObjValAs? String "op"
            let operand := sliceJson.getObjValAs? Json "operand"
            if op == .ok "neg" then
                match operand with
                | .ok j =>
                    let val := j.getObjVal? "value"
                    match val with
                    | .ok jVal =>
                        match jVal.getNat? with
                        | .ok n =>
                            let idx := -(n : Int)
                            let getIdent := mkIdent `PyAstLean.pyListGetItem
                            let iStx ← intToStx idx
                            `($getIdent $valueCode $iStx)
                        | _ =>
                            let sliceCode ← getCode sliceJson `term
                            let getIdent := mkIdent `getElem!
                            `($getIdent $valueCode $sliceCode)
                    | _ =>
                        let sliceCode ← getCode sliceJson `term
                        let getIdent := mkIdent `getElem!
                        `($getIdent $valueCode $sliceCode)
                | _ =>
                    let sliceCode ← getCode sliceJson `term
                    let getIdent := mkIdent `getElem!
                    `($getIdent $valueCode $sliceCode)
            else
                let sliceCode ← getCode sliceJson `term
                let getIdent := mkIdent `getElem!
                `($getIdent $valueCode $sliceCode)
        | _ =>
            let sliceCode ← getCode sliceJson `term
            let getIdent := mkIdent `getElem!
            `($getIdent $valueCode $sliceCode)
  | _, _ => throwError s!"Unsupported syntax category for Subscript node"

end PyAstLean
