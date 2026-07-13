import Mathlib
import PastaLean.PyAPI.ProofMode.IOStream
import PastaLean.PyAPI.Core

namespace PastaLean.ProofMode

/-- The state for proof-mode IO: an input stream and accumulated output. -/
structure IOState where
  /-- Input stream (infinite, indexed by Nat) -/
  input : IOStream
  /-- Accumulated output lines -/
  output : List String

-- Manual Inhabited instance (can't derive because IOStream has a function field)
instance : Inhabited IOState where
  default := {
    input := { pos := 0, str := fun _ => IOResult.error IOError.EndOfFile }
    output := []
  }

namespace IOError

/-- Convert an IOError to a PyException for integration with Python exception handling. -/
def toPyException : IOError → PastaLean.PyException
  | EndOfFile => ⟨"EOFError", "EOF when reading a line"⟩
  | ReadError msg => ⟨"IOError", msg⟩

end IOError

/-- The low-level proof monad: state with IO errors.
This monad models IO operations as pure state transformations with the possibility of IO errors. -/
abbrev InputM (α : Type) := ExceptT IOError (StateM IOState) α

/-- The high-level proof monad: state with Python exceptions.
This combines the InputM state with Python's exception system, allowing both IO errors
and Python exceptions (ValueError, etc.) to be caught uniformly by Python's except: handlers. -/
abbrev PyProofM (α : Type) := ExceptT PastaLean.PyException (StateM IOState) α

namespace PyProofM

/-- Lift an InputM action (which throws IOError) into PyProofM (which throws PyException).
This is the proof-mode equivalent of captureIOErrors: it converts IO-level errors into
catchable Python exceptions. -/
def liftInputM {α : Type} (action : InputM α) : PyProofM α :=
  fun s =>
    let (result, s') := action s
    match result with
    | Except.ok val => (Except.ok val, s')
    | Except.error ioErr => (Except.error ioErr.toPyException, s')

end PyProofM

/-- MonadLift instance to automatically lift InputM actions into PyProofM.
This allows writing `InputM.input` instead of `PyProofM.liftInputM InputM.input`. -/
instance : MonadLift InputM PyProofM where
  monadLift := PyProofM.liftInputM

namespace InputM

/-- Low-level input operation: consume one string from the stream.
Pattern matches on the IOResult at the current stream position:
- On success: advances the stream and returns the string
- On error: throws the IOError (will be converted to PyException by liftInputM) -/
def input : InputM String := do
  let s ← get
  match s.input.head with
  | IOResult.success str =>
    set { s with input := s.input.tail }
    return str
  | IOResult.error err =>
    throw err

/-- Low-level print operation: append a line to the output. -/
def print (line : String) : InputM Unit := do
  modify fun s => { s with output := s.output ++ [line] }

end InputM

end PastaLean.ProofMode
