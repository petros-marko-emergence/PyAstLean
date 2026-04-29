import PyAstLean.PyGens.Basic

open Lean

namespace PyAstLean

#eval 1 +ₚ 2
#eval "Hello, " +ₚ "World!"

#print fn

#eval fn 3
#check fn

#eval let m : Nat := n₀; m + (1 : Nat)

set_option pp.all true in
#print fnId

#eval py_term% onePlusTwoNode
#eval onePlusTwoNode.compress

def stringNatBinOpNode := json% {
    "node_type": "BinOp",
    "op": "add",
    "left": {
      "node_type": "Constant",
      "value": "Hello"
    },
    "right": {
      "node_type": "Constant",
      "value": 2
    }
  }

#eval show CoreM String from do
  match ← getCodeTermCore stringNatBinOpNode with
  | .ok fmt => return s!"unexpected success: {fmt}"
  | .error err => return err

#eval py_term% js₀

#eval py_term% {
  "node_type": "Constant",
  "value": "Hello, World!"
}

#eval py_term% {
  "node_type": "Constant",
  "value": -1.5
}

end PyAstLean
