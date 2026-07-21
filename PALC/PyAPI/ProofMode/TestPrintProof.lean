import PastaLean
open PastaLean.ProofMode
open PastaLean

-- Test pyPrintProof with simple arguments
def testSimplePrint : PyProofM Unit :=
  pyPrintProof [pyPrintArg "Hello", pyPrintArg "World"]

def runTestSimplePrint : Except PyException (Unit × IOState) :=
  testSimplePrint.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runTestSimplePrint
-- Expected: output should contain ["Hello World\n"]

-- Test pyPrintProof with numbers
def testNumberPrint : PyProofM Unit :=
  pyPrintProof [pyPrintArg (42 : Int), pyPrintArg (3.14 : Rat)]

def runTestNumberPrint : Except PyException (Unit × IOState) :=
  testNumberPrint.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runTestNumberPrint
-- Expected: output should contain ["42 1.57\n"] (rat prints as float)

-- Test pyPrintProof with custom separator
def testCustomSep : PyProofM Unit :=
  pyPrintProof [pyPrintArg "a", pyPrintArg "b", pyPrintArg "c"] ", " "\n"

def runTestCustomSep : Except PyException (Unit × IOState) :=
  testCustomSep.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runTestCustomSep
-- Expected: output should contain ["a, b, c\n"]

-- Test multiple prints accumulate
def testMultiplePrints : PyProofM Unit := do
  pyPrintProof [pyPrintArg "Line 1"]
  pyPrintProof [pyPrintArg "Line 2"]
  pyPrintProof [pyPrintArg "Line 3"]

def runTestMultiplePrints : Except PyException (Unit × IOState) :=
  testMultiplePrints.run ⟨IOStream.fromFun (fun _ => ""), []⟩

#eval runTestMultiplePrints
-- Expected: output should be ["Line 1\n", "Line 2\n", "Line 3\n"]
