import Mathlib
import Std.Tactic.Do

namespace Libraries.passta

set_option mvcgen.warning false

open Std.Do

/-! # PASSTA contract markers

Each contract function compiles to one of these. At runtime every marker is a no-op
(`pure ()`), so they never change behaviour. Their purpose is the `@[spec]` lemmas, which let
`mvcgen` reason about them, and their distinct names, which let the proof read by role and let
the `passta_vc` tactic tell a precondition from an invariant.

Two flavours:
* **prove** (`Assert`/`Ensures`/`Invariant`): to pass the checkpoint, `P` must hold here; `P` is
  then carried forward. Spec `⦃⌜P⌝⦄ … ⦃⇓ _ => ⌜P⌝⦄`.
* **drop** (`Requires`/`Assume`/`Decreases`): no obligation and nothing assumed at the checkpoint;
  `mvcgen` walks straight through. `Requires`/`Assume` instead surface as the triple's
  precondition (a `massume` checkpoint is unsound — it would prove `P` from nothing), and
  `Decreases` is data for the (future) `while` variant.
-/

-- prove-flavour ----------------------------------------------------------------------------------
def pyPassAssert    (_p : Prop) : Id Unit := pure ()
def pyPassEnsures   (_p : Prop) : Id Unit := pure ()
def pyPassInvariant (_p : Prop) : Id Unit := pure ()

@[spec] theorem pyPassAssert_spec (p : Prop) :
    ⦃⌜p⌝⦄ pyPassAssert p ⦃⇓ _ => ⌜p⌝⦄ := by
  mvcgen [pyPassAssert]
@[spec] theorem pyPassEnsures_spec (p : Prop) :
    ⦃⌜p⌝⦄ pyPassEnsures p ⦃⇓ _ => ⌜p⌝⦄ := by
    mvcgen [pyPassEnsures]
@[spec] theorem pyPassInvariant_spec (p : Prop) :
    ⦃⌜p⌝⦄ pyPassInvariant p ⦃⇓ _ => ⌜p⌝⦄ := by
  mvcgen [pyPassInvariant]

-- drop-flavour -----------------------------------------------------------------------------------
def pyPassRequires  (_p : Prop) : Id Unit := pure ()
def pyPassAssume    (_p : Prop) : Id Unit := pure ()
def pyPassDecreases {α} (_e : α) : Id Unit := pure ()

@[spec] theorem pyPassRequires_spec (p : Prop) :
    ⦃⌜True⌝⦄ pyPassRequires p ⦃⇓ _ => ⌜True⌝⦄ := by
  mvcgen [pyPassRequires]
@[spec] theorem pyPassAssume_spec (p : Prop) :
    ⦃⌜True⌝⦄ pyPassAssume p ⦃⇓ _ => ⌜True⌝⦄ := by
  mvcgen [pyPassAssume]
@[spec] theorem pyPassDecreases_spec {α} (e : α) :
    ⦃⌜True⌝⦄ pyPassDecreases e ⦃⇓ _ => ⌜True⌝⦄ := by
  mvcgen [pyPassDecreases]

/-- Back-compat alias used by the hand-written `mvcgen_eg` examples. -/
def massert (_p : Prop) : Id Unit := pure ()
@[spec] theorem massert_spec (p : Prop) :
    ⦃⌜p⌝⦄ massert p ⦃⇓ _ => ⌜p⌝⦄ := by mvcgen [massert]

end Libraries.passta
