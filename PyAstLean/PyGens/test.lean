-- This file is for testing the outputs

import PyAstLean.PyGens
import PyAstLean.PyGens.Basic
namespace PyAstLean

def pyprint_basic :=
  ((do
      let _ ←
        PyAstLean.pyPrintIO
            ["sum", (3 : Int), (4 : Int)]
      return (7 : Int)) :
    IO _)


#eval pyprint_basic

end PyAstLean
