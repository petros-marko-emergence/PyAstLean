import TypeInfer.PyType

/-!
# `PyType` → Lean type syntax

`toTypeSyntax?` turns a known `PyType` into the Lean type the runtime uses for it, and returns
`none` for anything still `unknown`/`any` — the caller then leaves the binder untyped (today) or
boxes it as `PyAny`.

`float` has no fixed answer: it is `ℚ` in exact mode, `ℝ` in a real-marked context and `Float`
under `--approx`. The caller resolves that and passes the type in as `floatTy`.
-/

namespace TypeInfer

open Lean

/-- The Lean type for a `PyType`; `none` if the type is not fully known.

`floatTy` is the caller's choice of `ℚ` / `ℝ` / `Float` for Python's `float`. -/
partial def toTypeSyntax? [Monad m] [MonadQuotation m]
    (floatTy : TSyntax `term) : PyType → m (Option (TSyntax `term))
  | .unknown | .any => return none
  | .int => return some (mkIdent ``Int)
  | .bool => return some (mkIdent ``Bool)
  | .str => return some (mkIdent ``String)
  | .float => return some floatTy
  | .none => return some (mkIdent ``Unit)
  | .cls n => return some (mkIdent n.toName)
  | .list e => do
      let some elem ← toTypeSyntax? floatTy e | return none
      return some (← `(List $elem))
  -- Sets are list-backed in the runtime (`PyAPI/Sets.lean`).
  | .set e => do
      let some elem ← toTypeSyntax? floatTy e | return none
      return some (← `(List $elem))
  | .opt e => do
      let some inner ← toTypeSyntax? floatTy e | return none
      return some (← `(Option $inner))
  | .dict k v => do
      let some key ← toTypeSyntax? floatTy k | return none
      let some val ← toTypeSyntax? floatTy v | return none
      return some (← `(Std.HashMap $key $val))
  | .tuple es => do
      let mut parts := #[]
      for e in es do
        let some part ← toTypeSyntax? floatTy e | return none
        parts := parts.push part
      -- `tuple[]` has no Lean counterpart; `tuple[a]` in Python is just `a`.
      match parts.toList with
      | [] => return none
      | [only] => return some only
      | first :: rest => return some (← rest.foldlM (fun acc p => `($acc × $p)) first)

end TypeInfer
