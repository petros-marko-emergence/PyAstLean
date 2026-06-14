import Mathlib

namespace Libraries.scipy

/-!
Python `scipy` runtime surface (a Mathlib-only, **computable** subset).

`scipy` leans heavily on transcendental functions whose Mathlib counterparts (`Real.Gamma`,
`Real.pi`, ...) are `noncomputable`, so generated Lean could not `#eval`/run them. We therefore
model the numeric core directly on Lean `Float`: exact combinatorics via `Nat.factorial` /
`Nat.choose`, and standard self-contained approximations (Lanczos for `gamma`,
Abramowitz–Stegun for `erf`). Everything here stays executable.
-/

/-- Types acceptable to the float-oriented `scipy` surface (mirrors the `math` shim). -/
class PyScipyFloatArg (α : Type) where
  toFloat : α → Float

export PyScipyFloatArg (toFloat)

instance : PyScipyFloatArg Float where toFloat := id
instance : PyScipyFloatArg Rat where toFloat := Rat.toFloat
instance : PyScipyFloatArg Int where toFloat x := Rat.toFloat (x : Rat)
instance : PyScipyFloatArg Nat where toFloat x := Rat.toFloat (x : Rat)
instance : PyScipyFloatArg Bool where toFloat b := if b then 1.0 else 0.0

/-- Maps a scipy scalar entry type to the numeric *field* its purely-algebraic reductions
(`tmean`, `hmean`, `det`, …) should compute in. `Float → Float` and `Rat → Rat` stay in their
own field (so exact-mode `ℚ` results compose with surrounding `ℚ` code and `--approx` `Float`
results are unchanged); integral/bool scalars promote to `Float`. Result type is an `outParam`. -/
class PyScipyCompute (α : Type) (γ : outParam Type) where
  cast : α → γ

instance : PyScipyCompute Float Float := ⟨id⟩
instance : PyScipyCompute Rat Rat := ⟨id⟩
instance : PyScipyCompute Int Float := ⟨fun x => Rat.toFloat (x : Rat)⟩
instance : PyScipyCompute Nat Float := ⟨fun x => Rat.toFloat (x : Rat)⟩
instance : PyScipyCompute Bool Float := ⟨fun b => if b then 1.0 else 0.0⟩
noncomputable instance : PyScipyCompute ℝ ℝ := ⟨id⟩

/-- `Nat → γ` for the numeric compute types. `Float` has NO Mathlib `NatCast` (it's an opaque
core type), so it can't use the generic `(n : γ)` coercion that `ℚ`/`ℝ` get — this bundles the
conversion so the algebraic stats below stay polymorphic across `Float`/`ℚ`/`ℝ`. -/
class PyOfNatScalar (γ : Type) where
  ofNatγ : Nat → γ

instance : PyOfNatScalar Float := ⟨Float.ofNat⟩
instance : PyOfNatScalar Rat := ⟨fun n => (n : Rat)⟩
noncomputable instance : PyOfNatScalar ℝ := ⟨fun n => (n : ℝ)⟩

/-- Sum a list of floats (no `List.sum` specialisation needed downstream). -/
private def fsum (xs : List Float) : Float :=
  xs.foldl (· + ·) 0.0

/-! ## scipy.constants -/

/-- `scipy.constants.pi`. -/
def pyScipyPi : Float := 3.141592653589793

/-- `scipy.constants.golden` / `golden_ratio` (the golden ratio φ). -/
def pyScipyGolden : Float := 1.618033988749895

/-! ## scipy.special -/

/-- `scipy.special.factorial` — exact via `Nat.factorial`, returned as a float (scipy default).
Negative inputs yield `0` as in scipy. -/
def pyScipyFactorial (n : Int) : Float :=
  if n < 0 then 0.0 else Float.ofNat (Nat.factorial n.toNat)

/-- `scipy.special.comb` — binomial coefficient C(n, k), exact via `Nat.choose`. -/
def pyScipyComb (n k : Int) : Float :=
  if n < 0 || k < 0 then 0.0 else Float.ofNat (Nat.choose n.toNat k.toNat)

/-- `scipy.special.perm` — number of permutations P(n, k), exact via `Nat.descFactorial`. -/
def pyScipyPerm (n k : Int) : Float :=
  if n < 0 || k < 0 then 0.0 else Float.ofNat (Nat.descFactorial n.toNat k.toNat)

/-- Lanczos coefficients (g = 7), highest-quality double-precision set. -/
private def lanczosG : Float := 7.0
private def lanczosC : List Float :=
  [ 0.99999999999980993, 676.5203681218851, -1259.1392167224028,
    771.32342877765313, -176.61502916214059, 12.507343278686905,
    -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7 ]

/-- Computable `scipy.special.gamma` via the Lanczos approximation (with the reflection
formula for the left half-plane). -/
partial def gammaFloat (x : Float) : Float :=
  if x < 0.5 then
    -- reflection: Γ(x)·Γ(1-x) = π / sin(πx)
    pyScipyPi / (Float.sin (pyScipyPi * x) * gammaFloat (1.0 - x))
  else
    let x := x - 1.0
    let a := lanczosC.headD 0.0
    let rest := lanczosC.tail
    -- a₀ + Σ cᵢ/(x+i)  for i = 1..8
    let a := (rest.zipIdx).foldl (init := a) (fun acc (c, i) =>
      acc + c / (x + Float.ofNat (i + 1)))
    let t := x + lanczosG + 0.5
    Float.sqrt (2.0 * pyScipyPi) * Float.exp ((x + 0.5) * Float.log t - t) * a

def pyScipyGamma {α : Type} [PyScipyFloatArg α] (x : α) : Float :=
  gammaFloat (toFloat x)

/-- Computable `scipy.special.erf` via the Abramowitz–Stegun 7.1.26 approximation
(|error| ≤ 1.5e-7). -/
def erfFloat (x : Float) : Float :=
  let sign := if x < 0.0 then -1.0 else 1.0
  let z := Float.abs x
  let t := 1.0 / (1.0 + 0.3275911 * z)
  let poly := ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t
                - 0.284496736) * t + 0.254829592) * t
  let y := 1.0 - poly * Float.exp (-z * z)
  sign * y

def pyScipyErf {α : Type} [PyScipyFloatArg α] (x : α) : Float :=
  erfFloat (toFloat x)

/-! ## Exact (`ℝ`) scipy scalars (default mode)

`noncomputable` `ℝ` versions of the scalar constants/specials that have a Mathlib equivalent
(`pi → Real.pi`, `gamma → Real.Gamma`). `erf` has no Mathlib `ℝ` form, so it stays `Float` and
needs `--approx` if combined with rationals. -/

/-- Inputs acceptable to the exact (`ℝ`) scipy surface (`ℚ`/`ℤ`/`ℕ`/`ℝ` → `ℝ`). -/
class PyScipyRealArg (α : Type) where
  toReal : α → ℝ

noncomputable instance : PyScipyRealArg ℝ := ⟨id⟩
noncomputable instance : PyScipyRealArg Rat := ⟨fun q => (q : ℝ)⟩
noncomputable instance : PyScipyRealArg Int := ⟨fun n => (n : ℝ)⟩
noncomputable instance : PyScipyRealArg Nat := ⟨fun n => (n : ℝ)⟩

noncomputable def pyScipyPiR : ℝ := Real.pi
noncomputable def pyScipyGammaR {α : Type} [PyScipyRealArg α] (x : α) : ℝ :=
  Real.Gamma (PyScipyRealArg.toReal x)

/-- `scipy.stats.gmean` over `ℝ` (exact mode): `exp(mean(log xs))` with Mathlib's `Real.*`. -/
noncomputable def pyScipyGmeanR {α : Type} [PyScipyRealArg α] (xs : List α) : ℝ :=
  let ys := xs.map PyScipyRealArg.toReal
  if ys.isEmpty then 0
  else Real.exp ((ys.map Real.log).foldl (· + ·) 0 / (ys.length : ℝ))

/-- `scipy.linalg.norm` over `ℝ` (exact mode): the Euclidean / Frobenius norm via `Real.sqrt`,
overloaded across vectors and matrices. -/
class ScipyRealNormable (α : Type) where
  scipyNormR : α → ℝ

noncomputable instance {β} [PyScipyRealArg β] : ScipyRealNormable (List β) where
  scipyNormR xs :=
    Real.sqrt ((xs.map (fun x => let r := PyScipyRealArg.toReal x; r * r)).foldl (· + ·) 0)

noncomputable instance {β} [PyScipyRealArg β] : ScipyRealNormable (List (List β)) where
  scipyNormR m :=
    Real.sqrt ((m.map (fun row =>
      (row.map (fun x => let r := PyScipyRealArg.toReal x; r * r)).foldl (· + ·) 0)).foldl (· + ·) 0)

noncomputable def pyScipyNormR {α : Type} [ScipyRealNormable α] (x : α) : ℝ :=
  ScipyRealNormable.scipyNormR x

/-! ## scipy.stats -/

/-- Sum a list over any additive type. -/
private def gsum {γ} [Add γ] [Zero γ] (xs : List γ) : γ := xs.foldl (· + ·) 0

/-- `scipy.stats.tmean` with no trimming limits — the arithmetic mean. Computes in the entries'
type (`ℚ` in exact mode, `Float` in `--approx`), so the result composes with surrounding code.
Constraints are the concrete ops used (NOT `Field`, which `Float` lacks). -/
def pyScipyTmean {α γ} [PyScipyCompute α γ] [Add γ] [Zero γ] [Div γ] [PyOfNatScalar γ]
    (xs : List α) : γ :=
  let ys := xs.map PyScipyCompute.cast
  if ys.isEmpty then 0 else gsum ys / PyOfNatScalar.ofNatγ ys.length

/-- `scipy.stats.hmean` — harmonic mean `n / Σ(1/xᵢ)`, computed in the entries' type. -/
def pyScipyHmean {α γ} [PyScipyCompute α γ] [Add γ] [Zero γ] [One γ] [Div γ] [PyOfNatScalar γ]
    (xs : List α) : γ :=
  let ys := xs.map PyScipyCompute.cast
  if ys.isEmpty then 0 else PyOfNatScalar.ofNatγ ys.length / gsum (ys.map (fun x => 1 / x))

/-- `scipy.stats.gmean` — geometric mean `exp(mean(log xs))`. Transcendental, so it stays on
`Float`; use `--approx`, or the `ℝ` variant `pyScipyGmeanR` selected in exact mode. -/
def pyScipyGmean {α} [PyScipyFloatArg α] (xs : List α) : Float :=
  let ys := xs.map toFloat
  if ys.isEmpty then 0.0 else Float.exp (fsum (ys.map Float.log) / Float.ofNat ys.length)

/-! ## scipy.linalg -/

/-- `scipy.linalg.norm`, overloaded over vectors and matrices (Frobenius for matrices). -/
class ScipyNormable (α : Type) where
  scipyNorm : α → Float

instance : ScipyNormable (List Float) where
  scipyNorm xs := Float.sqrt (fsum (xs.map (fun x => x * x)))

instance : ScipyNormable (List (List Float)) where
  scipyNorm m := Float.sqrt (fsum (m.map (fun row => fsum (row.map (fun x => x * x)))))

def pyScipyNorm {α : Type} [ScipyNormable α] (x : α) : Float :=
  ScipyNormable.scipyNorm x

/-- `scipy.linalg.det` via Laplace (cofactor) expansion along the first row, over any field
(`Float` in `--approx`, `ℚ` in exact mode). -/
partial def pyScipyDetField {γ} [Add γ] [Mul γ] [Neg γ] [Zero γ] [One γ] (m : List (List γ)) : γ :=
  match m with
  | [] => 1
  | [row] => row.headD 0
  | first :: _ =>
    let n := m.length
    (List.range n).foldl (init := 0) (fun acc j =>
      let minor := (m.drop 1).map (fun row => row.eraseIdx j)
      let sign : γ := if j % 2 == 0 then 1 else -1
      acc + sign * (first.getD j 0) * pyScipyDetField minor)

/-- `scipy.linalg.det` — determinant of a square matrix, computed in the entries' field. -/
def pyScipyDet {α γ} [PyScipyCompute α γ] [Add γ] [Mul γ] [Neg γ] [Zero γ] [One γ]
    (m : List (List α)) : γ :=
  pyScipyDetField (m.map (fun row => row.map PyScipyCompute.cast))

/-! ## scipy.integrate -/

/-- Element-wise `a + s · b` on equal-length float vectors. -/
private def vecAxpy (s : Float) (a b : List Float) : List Float :=
  (a.zip b).map (fun (x, y) => x + s * y)

/-- One classical RK4 step of `y' = f(y, t)` over a step of size `dt`. -/
private def rk4Step (f : List Float → Float → List Float) (y : List Float) (t dt : Float) :
    List Float :=
  let k1 := f y t
  let k2 := f (vecAxpy (dt / 2.0) y k1) (t + dt / 2.0)
  let k3 := f (vecAxpy (dt / 2.0) y k2) (t + dt / 2.0)
  let k4 := f (vecAxpy dt y k3) (t + dt)
  let incr := (k1.zip (k2.zip (k3.zip k4))).map (fun (a, b, c, d) => a + 2.0 * b + 2.0 * c + d)
  vecAxpy (dt / 6.0) y incr

/--
`scipy.integrate.odeint(f, y0, t)` — integrate the system `y' = f(y, t)` from initial state `y0`,
returning the state at every time in `t` (a row per time point, like SciPy).

Uses one fixed classical-RK4 step per output interval. SciPy uses adaptive LSODA, so for smooth
non-stiff systems the trajectories agree closely (not bit-for-bit). `f` takes `(state, t)` and
returns the derivative vector — exactly the Python signature `f(y, t)`.
-/
def pyScipyOdeint (f : List Float → Float → List Float) (y0 : List Float) (ts : List Float) :
    List (List Float) :=
  match ts with
  | [] => []
  | t0 :: rest =>
    let stepFn := fun (st : List (List Float) × List Float × Float) (tcur : Float) =>
      let (acc, yprev, tprev) := st
      let ynext := rk4Step f yprev tprev (tcur - tprev)
      (acc ++ [ynext], ynext, tcur)
    let (states, _, _) := rest.foldl stepFn ([y0], y0, t0)
    states

end Libraries.scipy
