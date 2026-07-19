import PastaLean.PyGens.Calls.SpecialCalls.Collections
import PastaLean.PyGens.Calls.SpecialCalls.Functools
import PastaLean.PyGens.Calls.SpecialCalls.Itertools

open Lean Meta Elab Term Qq Std

namespace PastaLean

/-- Try each registered special term-level call lowerer until one claims the call. -/
def lowerSpecialCallTerm? (funcJson : Json) (argsArray : Array Json) (argsCodes : Array (TSyntax `term))
    (keyWordsMap : PyKeywordArgs) : PygenM (Option (TSyntax `term)) := do
  match ← lowerFunctoolsCallTerm? funcJson argsArray argsCodes keyWordsMap with
  | some lowered => return some lowered
  | none =>
  match ← lowerItertoolsCallTerm? funcJson argsArray argsCodes keyWordsMap with
  | some lowered => return some lowered
  | none =>
  match ← lowerCollectionsCallTerm? funcJson argsArray argsCodes keyWordsMap with
  | some lowered => return some lowered
  | none => return none

/-- Try each registered special `doElem` call lowerer until one claims the call. -/
def lowerSpecialCallDoElem? (funcJson : Json) (argsArray : Array Json) (argsCodes : Array (TSyntax `term))
    (keyWordsMap : PyKeywordArgs) : PygenM (Option (TSyntax `doElem)) := do
  match ← lowerFunctoolsCallDoElem? funcJson argsArray argsCodes keyWordsMap with
  | some lowered => return some lowered
  | none =>
  match ← lowerItertoolsCallDoElem? funcJson argsArray argsCodes keyWordsMap with
  | some lowered => return some lowered
  | none => return none

/-- info: 2 -/
#guard_msgs in
#eval 1+1

end PastaLean
