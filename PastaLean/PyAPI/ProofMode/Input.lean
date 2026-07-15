import PastaLean.PyAPI.ProofMode.InputM

namespace PastaLean.ProofMode

/-- Proof-mode input operation (equivalent to pyInputIO in run mode).
Consumes one string from the input stream. If a prompt is provided, it is printed
to the output (mirroring pyInputIO's behavior). -/
def pyInputProof (prompt : String := "") : PyProofM String := do
  -- Print the prompt if provided (mirroring pyInputIO behavior)
  if !prompt.isEmpty then
    PyProofM.liftInputM (InputM.print prompt)
  -- Read from the input stream
  PyProofM.liftInputM InputM.input

end PastaLean.ProofMode
