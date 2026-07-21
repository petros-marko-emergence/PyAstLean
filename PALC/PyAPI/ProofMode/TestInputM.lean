import PastaLean
open PastaLean.ProofMode

-- Test basic IOStream operations
#eval (IOStream.fromFun (fun n => .success s!"input_{n}")).head  -- should be IOResult.success "input_0"
#eval (IOStream.fromFun (fun n => .success s!"input_{n}")).tail.head  -- should be IOResult.success "input_1"

-- Test EOF stream
#eval (IOStream.const (.error .EndOfFile)).head  -- should be IOResult.error IOError.EndOfFile

-- Test InputM.input operation
def testInput : InputM String := InputM.input

-- Run testInput with a success stream
def runTestInput : Except IOError (String × IOState) :=
  testInput.run ⟨IOStream.fromFun (fun n => .success s!"line_{n}"), []⟩

#eval runTestInput
-- Expected: Except.ok ("line_0", {input := {pos := 1, str := ...}, output := []})

-- Test InputM.input on EOF stream - should throw IOError
def testInputEOF : InputM String := InputM.input

def runTestInputEOF : Except IOError (String × IOState) :=
  testInputEOF.run ⟨IOStream.const (.error .EndOfFile), []⟩

#eval runTestInputEOF
-- Expected: Except.error IOError.EndOfFile

-- Test InputM.print operation
def testPrint : InputM Unit := InputM.print "hello"

def runTestPrint : Except IOError (Unit × IOState) :=
  testPrint.run ⟨IOStream.fromFun (fun _ => .success ""), []⟩

#eval runTestPrint
-- Expected: Except.ok ((), {input := ..., output := ["hello"]})

-- Test combined input and print
def testInputPrint : InputM Unit := do
  let line ← InputM.input
  InputM.print s!"Got: {line}"

def runTestInputPrint : Except IOError (Unit × IOState) :=
  testInputPrint.run ⟨IOStream.fromFun (fun n => .success s!"input_{n}"), []⟩

#eval runTestInputPrint
-- Expected: Except.ok ((), {input := {pos := 1, ...}, output := ["Got: input_0"]})

-- Test PyProofM with liftInputM
def testProofInput : PyProofM String :=
  PyProofM.liftInputM InputM.input

def runTestProofInput : Except PastaLean.PyException (String × IOState) :=
  testProofInput.run ⟨IOStream.fromFun (fun n => .success s!"data_{n}"), []⟩

#eval runTestProofInput
-- Expected: Except.ok ("data_0", {input := {pos := 1, ...}, output := []})

-- Test that IOError gets converted to PyException
def testIOErrorConversion : PyProofM String := do
  let line ← PyProofM.liftInputM InputM.input
  return line

def runWithEOF : Except PastaLean.PyException (String × IOState) :=
  testIOErrorConversion.run ⟨IOStream.const (.error .EndOfFile), []⟩

#eval runWithEOF
-- Expected: Except.error (PyException "EOFError" "EOF when reading a line")

-- Test finite stream (success until position N, then EOF)
def finiteStream (n : Nat) : IOStream :=
  IOStream.fromFun (fun i => if i < n then .success s!"line_{i}" else .error .EndOfFile)

def testFiniteStream : InputM (List String) := do
  let mut lines := []
  for _ in [0:5] do
    let line ← InputM.input
    lines := lines ++ [line]
  return lines

def runFiniteStream : Except IOError (List String × IOState) :=
  testFiniteStream.run ⟨finiteStream 3, []⟩

#eval runFiniteStream
-- Expected: Except.error IOError.EndOfFile (throws on 4th read)
