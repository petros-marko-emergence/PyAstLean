import Lean

/-!
A linter that flags every `PyAny` binder emitted when type inference could not determine a
concrete type. `PyAny` is total (it runs) but not provable — so in prove mode each occurrence gets
a warning asking the user to annotate the real type. It is off by default; the code generator turns
it on (`set_option linter.pyAnyProof true`) only in the preamble of a file that has a prove twin.
-/

open Lean Elab Command

namespace PastaLean.Linter

register_option linter.pyAnyProof : Bool := {
  defValue := false
  descr := "warn on `PyAny` binders (an un-inferred type) that block proving"
}

/-- True for an identifier whose final component is `PyAny`. -/
private def isPyAnyName (nm : Name) : Bool :=
  match nm.eraseMacroScopes with
  | .str _ s => s == "PyAny"
  | _ => false

/-- Collect every identifier occurrence of `PyAny` in a syntax tree. -/
private partial def collect : Syntax → Array Syntax → Array Syntax
  | stx@(Syntax.ident ..), acc => if isPyAnyName stx.getId then acc.push stx else acc
  | Syntax.node _ _ args, acc => args.foldl (fun a s => collect s a) acc
  | _, acc => acc

/-- The linter: warn at each `PyAny` use site. -/
def pyAnyProofLinter : Linter where
  run := fun stx => do
    unless Linter.getLinterValue linter.pyAnyProof (← Linter.getLinterOptions) do
      return
    for occ in collect stx #[] do
      Linter.logLint linter.pyAnyProof occ
        m!"Proving may not work with PyAny (type inference could not determine a concrete type). \
           Please annotate the correct type."

initialize addLinter pyAnyProofLinter

end PastaLean.Linter
