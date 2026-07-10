import Mathlib
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace Libraries.itertools

/-- `itertools.pairwise(xs)`: successive overlapping pairs. `pyPairwise [a, b, c] = [(a,b), (b,c)]`,
and `[]` for inputs shorter than two. -/
def pyPairwise {α β : Type} [PastaLean.PyIterable α β] (xs : α) : List (β × β) :=
  let items := PastaLean.pyIter xs
  items.zip items.tail

/-- `itertools.accumulate(xs)`: running totals. `pyAccumulate [1, 2, 3] = [1, 3, 6]`, `[] = []`. -/
def pyAccumulate {α : Type} [Add α] : List α → List α
  | [] => []
  | x :: rest => rest.scanl (· + ·) x

/-- `itertools.chain(*iterables)`: concatenate in order. `pyChain [[1,2], [], [3]] = [1,2,3]`. -/
def pyChain {α β : Type} [PastaLean.PyIterable α β] (xss : List α) : List β :=
  xss.flatMap PastaLean.pyIter

end Libraries.itertools
