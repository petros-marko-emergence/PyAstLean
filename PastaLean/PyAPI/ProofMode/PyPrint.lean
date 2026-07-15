import PastaLean.PyAPI.ProofMode.InputM
import PastaLean.PyAPI.PyPrint

namespace PastaLean.ProofMode

/-- Proof-mode print operation (equivalent to pyPrintIO in run mode).
Accumulates output to the state's output list. Reuses the existing PyPrintable
infrastructure for consistent formatting between run and proof modes. -/
def pyPrintProof (parts : List PastaLean.PyPrintArg) (sep : String := " ") (ending : String := "\n") :
    PyProofM Unit := do
  -- Render using the same formatting logic as pyPrintIO
  let rendered := PastaLean.pyPrintArgsRendered parts sep ending
  -- Append to the output accumulator
  modify fun s => { s with output := s.output ++ [rendered] }

end PastaLean.ProofMode
