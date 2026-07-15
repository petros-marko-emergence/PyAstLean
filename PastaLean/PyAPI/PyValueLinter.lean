import Lean

/-!
A linter that flags every `PyValue` binder emitted when type inference could not determine a
concrete type. `PyValue` is total (it runs) but not provable — so in prove mode each occurrence gets
a warning asking the user to annotate the real type. It is off by default; the code generator turns
it on (`set_option linter.pyValueProof true`) only in the preamble of a file that has a prove twin.
-/

open Lean Elab Command

namespace PastaLean.Linter

register_option linter.pyValueProof : Bool := {
  defValue := false
  descr := "warn on `PyValue` binders (an un-inferred type) that block proving"
}

/-- True for an identifier whose final component is `PyValue`. -/
private def isPyValueName (nm : Name) : Bool :=
  match nm.eraseMacroScopes with
  | .str _ s => s == "PyValue"
  | _ => false

/-- Collect every identifier occurrence of `PyValue` in a syntax tree. -/
private partial def collect : Syntax → Array Syntax → Array Syntax
  | stx@(Syntax.ident ..), acc => if isPyValueName stx.getId then acc.push stx else acc
  | Syntax.node _ _ args, acc => args.foldl (fun a s => collect s a) acc
  | _, acc => acc

/-- The linter: warn at each `PyValue` use site. -/
def pyValueProofLinter : Linter where
  run := fun stx => do
    unless Linter.getLinterValue linter.pyValueProof (← Linter.getLinterOptions) do
      return
    for occ in collect stx #[] do
      Linter.logLint linter.pyValueProof occ
        m!"Proving may not work with PyValue (type inference could not determine a concrete type). \
           Please annotate the correct type."

initialize addLinter pyValueProofLinter

end PastaLean.Linter
