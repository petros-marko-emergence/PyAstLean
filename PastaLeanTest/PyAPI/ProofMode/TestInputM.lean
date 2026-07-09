import PastaLean
open PastaLean.ProofMode

-- Test basic IOStream operations
#eval (IOStream.fromFun (fun n => s!"input_{n}")).head  -- should be "input_0"
#eval (IOStream.fromFun (fun n => s!"input_{n}")).tail.head  -- should be "input_1"

-- Test InputM.input operation
def testInput : InputM String := InputM.input

-- Run testInput with a simple stream
def runTestInput : Except IOError (String × IOState) :=
  testInput.run ⟨IOStream.fromFun (fun n => s!"line_{n}"), []⟩

#eval runTestInput
-- Expected: Except.ok ("line_0", {input := {pos := 1, str := ...}, output := []})

-- Test InputM.print operation
def testPrint : InputM Unit := InputM.print "hello"

def runTestPrint : Except IOError (Unit × IOState) :=
  testPrint.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runTestPrint
-- Expected: Except.ok ((), {input := ..., output := ["hello"]})

-- Test combined input and print
def testInputPrint : InputM Unit := do
  let line ← InputM.input
  InputM.print s!"Got: {line}"

def runTestInputPrint : Except IOError (Unit × IOState) :=
  testInputPrint.run ⟨IOStream.fromFun (fun n => s!"input_{n}"), []⟩

#eval runTestInputPrint
-- Expected: Except.ok ((), {input := {pos := 1, ...}, output := ["Got: input_0"]})

-- Test PyProofM with liftInputM
def testProofInput : PyProofM String :=
  PyProofM.liftInputM InputM.input

def runTestProofInput : Except PastaLean.PyException (String × IOState) :=
  testProofInput.run ⟨IOStream.fromFun (fun n => s!"data_{n}"), []⟩

#eval runTestProofInput
-- Expected: Except.ok ("data_0", {input := {pos := 1, ...}, output := []})

-- Test that IOError gets converted to PyException
def testIOErrorConversion : PyProofM String := do
  let line ← PyProofM.liftInputM InputM.input
  return line

def runWithEOF : Except PastaLean.PyException (String × IOState) :=
  testIOErrorConversion.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runWithEOF
-- Should succeed (no EOF in our simple model yet, but conversion is there)
