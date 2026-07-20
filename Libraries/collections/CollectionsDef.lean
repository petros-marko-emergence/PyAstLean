import Mathlib
import PastaLean.PyAPI

namespace Libraries.collections

open PastaLean

/-- A dict whose missing keys read as `dflt` instead of raising `KeyError`. Models both
`collections.Counter` (`dflt = 0`) and `collections.defaultdict(f)` (`dflt = f ()`).

`order` lists the keys by first insertion, so `keys`/`values`/`items`/iteration match Python's
insertion-ordered dicts rather than the hash order of `map`. -/
structure PyDefaultDict (κ ν : Type) [BEq κ] [Hashable κ] where
  map : Std.HashMap κ ν
  order : List κ
  dflt : ν

variable {κ ν : Type} [BEq κ] [Hashable κ]

/-- `defaultdict(f)` / `Counter()`: empty, reading missing keys as `dflt`. -/
def PyDefaultDict.empty (dflt : ν) : PyDefaultDict κ ν := ⟨∅, [], dflt⟩

/-- Set `k` to `v`, recording `k` at the end of `order` when it is new. -/
def PyDefaultDict.insert (d : PyDefaultDict κ ν) (k : κ) (v : ν) : PyDefaultDict κ ν :=
  { d with
    map := d.map.insert k v,
    order := if d.map.contains k then d.order else d.order ++ [k] }

/-- The `(key, value)` pairs in insertion order. -/
def PyDefaultDict.toPairs (d : PyDefaultDict κ ν) : List (κ × ν) :=
  d.order.filterMap (fun k => (d.map.get? k).map (fun v => (k, v)))

/-- Count occurrences of each element: `ofIterable ['a','b','a'] = {'a' ↦ 2, 'b' ↦ 1}`. -/
def PyDefaultDict.ofIterable {α : Type} [PyIterable α κ] (xs : α) : PyDefaultDict κ Int :=
  (pyIter xs).foldl (fun d k => d.insert k (d.map.getD k 0 + 1)) (PyDefaultDict.empty 0)

/-- `collections.defaultdict(list)`. -/
def pyDefaultDictList : PyDefaultDict κ (List ν) := PyDefaultDict.empty []

/-- `collections.defaultdict(int)`. -/
def pyDefaultDictInt : PyDefaultDict κ Int := PyDefaultDict.empty 0

/-- `collections.Counter()`. -/
def pyCounterEmpty : PyDefaultDict κ Int := PyDefaultDict.empty 0

/-- `collections.Counter(xs)`. -/
def pyCounter {α : Type} [PyIterable α κ] (xs : α) : PyDefaultDict κ Int :=
  PyDefaultDict.ofIterable xs

/-- `collections.deque()`. Deques are `List`-backed, so every list protocol applies to them. -/
def pyDequeEmpty {α : Type} : List α := []

/-- `collections.deque(xs)`: `pyDeque "ab" = ["a", "b"]`. -/
def pyDeque {α β : Type} [PyIterable α β] (xs : α) : List β := pyIter xs

/-- `d[k]` yields `d.dflt` when `k` is absent; unlike Python it does not insert the key. -/
instance : PyGetItem (PyDefaultDict κ ν) κ ν where
  getItem d k := d.map.getD k d.dflt

instance : PySetItem (PyDefaultDict κ ν) κ ν where
  setItem d k v := d.insert k v

instance : PyLen (PyDefaultDict κ ν) where
  pyLen d := d.map.size

instance : PyIterable (PyDefaultDict κ ν) κ where
  toPyList d := d.order

instance : PyContains (PyDefaultDict κ ν) κ where
  contains d k := d.map.contains k

instance : PyClear (PyDefaultDict κ ν) where
  pyClear d := { d with map := ∅, order := [] }

instance : PyItems (PyDefaultDict κ ν) κ ν where
  pyItems d := d.toPairs

instance : PyKeys (PyDefaultDict κ ν) κ where
  pyKeys d := d.order

instance : PyAnys (PyDefaultDict κ ν) ν where
  pyAnys d := d.toPairs.map Prod.snd

end Libraries.collections
