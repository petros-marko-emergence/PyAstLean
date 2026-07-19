import Mathlib
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace Libraries.itertools

/-! Runtime for Python's `itertools`. Iterators become strict `List`s, so genuinely infinite ones
(`count`, `cycle`, unbounded `repeat`) are not provided — they can't be a finite list. A "tuple" from
`product`/`combinations`/`permutations` is a `List` (Lean has no variadic tuple type). -/

/-- `itertools.pairwise(xs)`: successive overlapping pairs. `pyPairwise [a,b,c] = [(a,b),(b,c)]`. -/
def pyPairwise {α β : Type} [PastaLean.PyIterable α β] (xs : α) : List (β × β) :=
  let items := PastaLean.pyIter xs
  items.zip items.tail

/-- `itertools.accumulate(xs, initial=…)`: running sums. `pyAccumulate [1,2,3] = [1,3,6]`;
`pyAccumulate [1,2,3] (some 100) = [100,101,103,106]`. -/
def pyAccumulate {α : Type} [Add α] (xs : List α) (initial : Option α := none) : List α :=
  match (match initial with | some v => v :: xs | none => xs) with
  | [] => []
  | x :: rest => rest.scanl (· + ·) x

/-- `itertools.chain(*iterables)` / `chain.from_iterable(xss)`: concatenate in order. -/
def pyChain {α β : Type} [PastaLean.PyIterable α β] (xss : List α) : List β :=
  xss.flatMap PastaLean.pyIter

/-- `itertools.product(*iterables)`: Cartesian product; each result tuple is a list. -/
def pyProduct {α β : Type} [PastaLean.PyIterable α β] (xss : List α) : List (List β) :=
  xss.foldl (fun acc xs => acc.flatMap (fun pre => (PastaLean.pyIter xs).map (fun y => pre ++ [y]))) [[]]

/-- `itertools.compress(data, selectors)`: keep the `data` elements whose selector is true. -/
def pyCompress {α : Type} (data : List α) (selectors : List Bool) : List α :=
  (data.zip selectors).filterMap (fun (x, sel) => if sel then some x else none)

/-- `itertools.combinations(iterable, r)`: r-length subsequences keeping order.
`pyCombinations [1,2,3] 2 = [[1,2],[1,3],[2,3]]`. -/
partial def pyCombinations {α β : Type} [PastaLean.PyIterable α β] (xs : α) (r : Int) : List (List β) :=
  go r.toNat (PastaLean.pyIter xs)
where
  go : Nat → List β → List (List β)
    | 0, _ => [[]]
    | _ + 1, [] => []
    | k + 1, h :: t => ((go k t).map (h :: ·)) ++ go (k + 1) t

/-- `itertools.combinations_with_replacement(iterable, r)`: like `combinations` but with repeats. -/
partial def pyCombinationsWithReplacement {α β : Type} [PastaLean.PyIterable α β]
    (xs : α) (r : Int) : List (List β) :=
  go r.toNat (PastaLean.pyIter xs)
where
  go : Nat → List β → List (List β)
    | 0, _ => [[]]
    | _ + 1, [] => []
    | k + 1, h :: t => ((go k (h :: t)).map (h :: ·)) ++ go (k + 1) t

/-- `itertools.permutations(iterable, r)`: r-length ordered arrangements, no repeats.
`pyPermutations [1,2,3] 2 = [[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]]`. -/
partial def pyPermutations {α β : Type} [PastaLean.PyIterable α β] (xs : α) (r : Int) : List (List β) :=
  go r.toNat (PastaLean.pyIter xs)
where
  go : Nat → List β → List (List β)
    | 0, _ => [[]]
    | _ + 1, [] => []
    | k + 1, items => (List.range items.length).flatMap (fun i =>
        match items[i]? with
        | some h => (go k (items.eraseIdx i)).map (h :: ·)
        | none => [])

/-- `itertools.groupby(iterable)`: group CONSECUTIVE equal elements (identity key).
`pyGroupby [1,1,2,3,3] = [(1,[1,1]),(2,[2]),(3,[3,3])]`. -/
def pyGroupby {α β : Type} [PastaLean.PyIterable α β] [DecidableEq β] (xs : α) : List (β × List β) :=
  (PastaLean.pyIter xs).foldr (fun x acc =>
    match acc with
    | (k, g) :: rest => if x = k then (k, x :: g) :: rest else (x, [x]) :: (k, g) :: rest
    | [] => [(x, [x])]) []

/-- `itertools.batched(iterable, n)`: consecutive n-length chunks (last may be shorter).
`pyBatched "ABCDEFG" 3 = [['A','B','C'],['D','E','F'],['G']]` (as lists). -/
partial def pyBatched {α β : Type} [PastaLean.PyIterable α β] (xs : α) (n : Int) : List (List β) :=
  go (PastaLean.pyIter xs)
where
  go : List β → List (List β)
    | [] => []
    | items => if n < 1 then [] else items.take n.toNat :: go (items.drop n.toNat)

/-- `itertools.tee(iterable, n)`: `n` independent copies. -/
def pyTee {α β : Type} [PastaLean.PyIterable α β] (xs : α) (n : Int := 2) : List (List β) :=
  List.replicate n.toNat (PastaLean.pyIter xs)

/-- `itertools.repeat(elem, n)`: `elem` repeated `n` times (finite form only). -/
def pyRepeat {β : Type} (elem : β) (n : Int) : List β :=
  List.replicate n.toNat elem

/-- `itertools.islice(iterable, stop)`: the first `stop` elements. -/
def pyIslice {α β : Type} [PastaLean.PyIterable α β] (xs : α) (stop : Int) : List β :=
  (PastaLean.pyIter xs).take stop.toNat

/-- `itertools.dropwhile(pred, xs)`: drop the leading run where `pred` holds, keep the rest. -/
def pyDropwhile {α β : Type} [PastaLean.PyIterable α β] (pred : β → Bool) (xs : α) : List β :=
  (PastaLean.pyIter xs).dropWhile pred

/-- `itertools.takewhile(pred, xs)`: the leading run where `pred` holds. -/
def pyTakewhile {α β : Type} [PastaLean.PyIterable α β] (pred : β → Bool) (xs : α) : List β :=
  (PastaLean.pyIter xs).takeWhile pred

/-- `itertools.filterfalse(pred, xs)`: the elements where `pred` is false. -/
def pyFilterfalse {α β : Type} [PastaLean.PyIterable α β] (pred : β → Bool) (xs : α) : List β :=
  (PastaLean.pyIter xs).filter (fun x => ! pred x)

/-- `itertools.starmap(f, xs)`: `f(*t)` for each pair `t` in `xs` (2-tuple form). -/
def pyStarmap {β γ : Type} (f : β → β → γ) (xs : List (β × β)) : List γ :=
  xs.map (fun (a, b) => f a b)

/-- `itertools.zip_longest(a, b, fillvalue)`: pair up to the longer, padding with `fillvalue`. -/
def pyZipLongest {β : Type} (fillvalue : β) (a b : List β) : List (β × β) :=
  (List.range (max a.length b.length)).map (fun i => (a[i]?.getD fillvalue, b[i]?.getD fillvalue))

end Libraries.itertools
