import Lean
import PastaLean
import TypeInfer
import PALC

/-!
# PastaCheck — the example-program test runner (`lake test`)

Two things run under `lake test`:

1. **`#guard_msgs` / `#guard` unit tests** in the `PALC` library — these fire at *build* time, so
   importing `PALC` above makes `lake build` of this executable fail if any of them fail.
2. **Every Python program in `example_scripts/`** — all are translated in one warm pass
   (`pastalean batch --emit-lean`; the Python front end still owns AST→JSON), then each is
   **compile-checked in-process** by elaborating the generated Lean in the already-booted Mathlib
   environment (no `lake env lean` per file). A program passes when it converts, carries no
   unexpected `pyUnsupported`, and elaborates clean.

Generated `.lean` is written next to the `.py` for the "showcase" directories (so the output is
reviewable), and checked-then-discarded for the rest.
-/

open Lean Lean.Elab

def backendModules : Array Import :=
  #[{ module := `PastaLean }, { module := `Mathlib }, { module := `Libraries }]

unsafe def bootEnv : IO Environment := do
  initSearchPath (← findSysroot)
  enableInitializersExecution
  importModules (loadExts := true) backendModules {}

/-- Drop `import …` lines: the environment already has everything imported. -/
def stripImports (code : String) : String :=
  String.intercalate "\n" ((code.splitOn "\n").filter (fun l => ¬ l.trimAscii.startsWith "import "))

/-- Elaborate a generated program in `env`; `none` on success, else the first error message. -/
def checkProgram (env : Environment) (code : String) : IO (Option String) := do
  let src := stripImports code
  let inputCtx := Parser.mkInputContext src "<check>"
  let cmdState := Command.mkState env {} {}
  let frontendState ← Lean.Elab.IO.processCommands inputCtx {} cmdState
  let msgs := frontendState.commandState.messages
  unless msgs.hasErrors do return none
  for msg in msgs.toList do
    if msg.severity == .error then
      let s := (← msg.data.toString).trimAscii.toString
      return some ((s.replace "\n" " ").take 160).toString
  return some "elaboration error"

/-- Translate every `.py` under `dir` through ONE warm backend (`pastalean batch --emit-lean`), and
return the parsed summary records `{file, status, error?, unsupported?, lean?}`. This is the single
expensive step (one Mathlib boot); the compile-checks that follow are all in-process. -/
def translateAll (pyBin : String) (dir : System.FilePath) : IO (Array Json) := do
  let summaryPath : System.FilePath := "/tmp/pastacheck_summary.json"
  let out ← IO.Process.output {
    cmd := pyBin,
    args := #["-m", "pastalean", "batch", dir.toString, "--recursive", "--mode", "both",
              "--emit-lean", "--summary", summaryPath.toString, "--quiet"] }
  unless (← summaryPath.pathExists) do
    throw (IO.userError s!"pastalean batch produced no summary:\n{out.stderr}")
  match Json.parse (← IO.FS.readFile summaryPath) with
  | .ok j => return (j.getObjValAs? (Array Json) "files").toOption.getD #[]
  | .error e => throw (IO.userError s!"could not parse batch summary: {e}")

/-- Files where a `pyUnsupported` placeholder is expected (best-effort degradation demos). -/
def expectUnsupported : List String := ["unsupported_demo.py"]

/-- Directories whose generated `.lean` is written next to the `.py` (reviewable output). -/
def writeInPlaceDirs : List String := ["showcase", "mvcgen_playground", "random"]

/-- Non-program helper scripts (drivers/figures), not transpiler inputs. -/
def skipNames : List String := ["run_showcase.py", "fetch_data.py"]

/-- Directories skipped by the per-file checker: `terms/` are single expressions (`--target term`),
and `imports/` are a cross-file import test that needs the imported module elaborated first (a
multi-file check this per-file runner doesn't do). -/
def skipDirs : List String := ["terms", "imports"]

/-- The verdict for one program. -/
inductive Verdict | ok | convertFail (msg : String) | unsupported (msg : String) | compileFail (msg : String)

def Verdict.tag : Verdict → String
  | .ok => "OK" | .convertFail _ => "CONVERT_FAIL"
  | .unsupported _ => "UNSUPPORTED" | .compileFail _ => "COMPILE_FAIL"

def Verdict.detail : Verdict → String
  | .ok => "" | .convertFail m | .unsupported m | .compileFail m => m

/-- Verdict for one already-translated summary record. -/
def checkRecord (env : Environment) (rec : Json) : IO (Option Verdict) := do
  let file := (rec.getObjValAs? String "file").toOption.getD ""
  let name := (System.FilePath.mk file).fileName.getD ""
  if skipNames.contains name then return none          -- driver/figure scripts, not programs
  if skipDirs.any (fun d => (file.splitOn s!"/{d}/").length > 1) then return none
  let status := (rec.getObjValAs? String "status").toOption.getD "convert_fail"
  if status == "convert_fail" then
    return some (.convertFail ((rec.getObjValAs? String "error").toOption.getD "convert failed"))
  let hasUnsup := (rec.getObjVal? "unsupported").toOption.isSome
  let expects := expectUnsupported.contains name
  if hasUnsup && !expects then
    return some (.unsupported "unexpected pyUnsupported placeholder(s) — real logic degraded")
  if expects && !hasUnsup then
    return some (.unsupported "expected pyUnsupported placeholder(s) but found none")
  let code := (rec.getObjValAs? String "lean").toOption.getD ""
  -- Write `.lean` next to the `.py` for the reviewable showcase directories.
  if writeInPlaceDirs.any (fun d => (file.splitOn s!"/{d}/").length > 1) then
    IO.FS.writeFile ((System.FilePath.mk file).withExtension "lean") code
  match ← checkProgram env code with
  | some err => return some (.compileFail err)
  | none => return some .ok

unsafe def main (args : List String) : IO UInt32 := do
  let base : System.FilePath := "example_scripts"
  -- Optional first arg restricts to one subdirectory (`lake exe pastacheck typing`).
  let dir := match args.head? with | some g => base / g | none => base
  let pyBin := if (← (System.FilePath.mk ".venv/bin/python3").pathExists) then ".venv/bin/python3" else "python3"
  IO.println "Translating every example (one warm backend)…"
  let records ← translateAll pyBin dir
  IO.println "Booting Mathlib environment for in-process compile-checks…"
  let env ← bootEnv
  let mut ok := 0
  let mut fails := 0
  for rec in records.qsort (fun a b => (a.getObjValAs? String "file").toOption.getD "" < (b.getObjValAs? String "file").toOption.getD "") do
    match ← checkRecord env rec with
    | none => pure ()
    | some v =>
        let rel := (rec.getObjValAs? String "file").toOption.getD ""
        match v with
        | .ok => ok := ok + 1; IO.println s!"  OK            {rel}"
        | _ => fails := fails + 1; IO.println s!"  {v.tag}  {rel}: {v.detail}"
  IO.println s!"\n=== {ok} OK, {fails} FAILED ==="
  return if fails == 0 then 0 else 1
