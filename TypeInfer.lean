import TypeInfer.PyType
import TypeInfer.Annotation
import TypeInfer.Value
import TypeInfer.Emit
import TypeInfer.Rules
import TypeInfer.Solve

/-!
# TypeInfer — what type is this Python value?

A small, self-contained analysis: `PyType` (the lattice), `ofAnnotation` (read a Python annotation),
`ofValue` (read a literal's shape), and `toTypeSyntax?` (emit the Lean type).

It depends only on `Lean.Json`, so `PyGens` can import it without a cycle. See `TypeInfer/README.md`.
-/
