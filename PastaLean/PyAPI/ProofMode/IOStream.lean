import Mathlib

namespace PastaLean.ProofMode

/-- An infinite stream of strings indexed by position.
This models the input available to a program in proof mode. -/
structure IOStream where
  /-- Current position in the stream (how many inputs have been consumed) -/
  pos : Nat
  /-- The stream function: maps each position to the string at that position -/
  str : Nat → String

namespace IOStream

/-- Get the current element (at position `pos`) from the stream. -/
def head (s : IOStream) : String :=
  s.str s.pos

/-- Advance the stream by one position. -/
def tail (s : IOStream) : IOStream :=
  ⟨s.pos + 1, s.str⟩

/-- Create a stream from a constant string (repeats forever). -/
def const (s : String) : IOStream :=
  ⟨0, fun _ => s⟩

/-- Create a stream from a function, starting at position 0. -/
def fromFun (f : Nat → String) : IOStream :=
  ⟨0, f⟩

end IOStream

end PastaLean.ProofMode
