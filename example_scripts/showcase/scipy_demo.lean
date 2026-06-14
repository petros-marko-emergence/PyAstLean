import PyAstLean
import Libraries

open PyAstLean
open Libraries

/-
A small numeric-toolkit showcase: `typing` annotations + a `scipy` subset, all transpiled
to Lean 4 and backed only by Mathlib (computable Float implementations).
-/
def variance := fun (xs : List Rat) ↦
  Id.run
    (do
      let mut m := Libraries.scipy.pyScipyTmean xs
      let mut total := (0.0 : Rat)
      for x in (PyAstLean.pyIter xs)do
        total := total +ₚ (x -ₚ m) *ₚ (x -ₚ m)
      let __py_ret := total /ₚ PyAstLean.pyLen xs
      return __py_ret)

noncomputable def main' :=
  ((do
      let mut data :=
        [(2.0 : Rat), (4.0 : Rat), (4.0 : Rat), (4.0 : Rat), (5.0 : Rat), (5.0 : Rat), (7.0 : Rat), (9.0 : Rat)]
      let _ ← pyPrintIO [pyPrintArg "=== scipy.special ==="]
      let _ ← pyPrintIO [pyPrintArg "5!        =", pyPrintArg (Libraries.scipy.pyScipyFactorial (5 : Int))]
      let _ ← pyPrintIO [pyPrintArg "C(8,3)    =", pyPrintArg (Libraries.scipy.pyScipyComb (8 : Int) (3 : Int))]
      let _ ← pyPrintIO [pyPrintArg "gamma(6)  =", pyPrintArg (Libraries.scipy.pyScipyGammaR (6.0 : Rat))]
      let _ ← pyPrintIO [pyPrintArg "erf(1)    =", pyPrintArg (Libraries.scipy.pyScipyErf (1.0 : Rat))]
      let _ ← pyPrintIO [pyPrintArg "=== scipy.constants ==="]
      let _ ← pyPrintIO [pyPrintArg "pi        =", pyPrintArg Libraries.scipy.pyScipyPiR]
      let _ ← pyPrintIO [pyPrintArg "golden    =", pyPrintArg Libraries.scipy.pyScipyGolden]
      let _ ← pyPrintIO [pyPrintArg "=== scipy.stats ==="]
      let _ ← pyPrintIO [pyPrintArg "mean      =", pyPrintArg (Libraries.scipy.pyScipyTmean data)]
      let _ ← pyPrintIO [pyPrintArg "gmean     =", pyPrintArg (Libraries.scipy.pyScipyGmeanR data)]
      let _ ← pyPrintIO [pyPrintArg "hmean     =", pyPrintArg (Libraries.scipy.pyScipyHmean data)]
      let _ ← pyPrintIO [pyPrintArg "variance  =", pyPrintArg (variance data)]
      let _ ← pyPrintIO [pyPrintArg "=== scipy.linalg ==="]
      let mut matrix := [[(4.0 : Rat), (3.0 : Rat)], [(6.0 : Rat), (3.0 : Rat)]]
      let _ ← pyPrintIO [pyPrintArg "det       =", pyPrintArg (Libraries.scipy.pyScipyDet matrix)]
      let _ ←
        pyPrintIO [pyPrintArg "norm[3,4] =", pyPrintArg (Libraries.scipy.pyScipyNormR [(3.0 : Rat), (4.0 : Rat)])]) :
    IO _)

noncomputable def main : IO Unit := do
  let _ ← main'
  pure ()
