import Mathlib
import PastaLean.PyAPI.CommonProtocols.Iterable

namespace Libraries.heapq

/-! Python's `heapq`. A heap is modelled as an ascending-sorted list (the min is the head), so the
ordering invariant is trivially maintained; ops are O(n log n) rather than O(log n), but correct. The
mutating calls (`heapify`/`heappush`/`heappop`) are lowered to reassignments of the heap variable by
`PyGens/Calls/SpecialCalls/Heapq.lean`. -/

private def sortAsc {α : Type} [LinearOrder α] (xs : List α) : List α :=
  xs.mergeSort (fun a b => decide (a ≤ b))

/-- `heapq.heapify(h)`: reorder into a (sorted) heap. -/
def pyHeapify {α : Type} [LinearOrder α] (xs : List α) : List α := sortAsc xs

/-- `heapq.heappush(h, x)`: add `x`, keeping the heap ordered. -/
def pyHeappush {α : Type} [LinearOrder α] (h : List α) (x : α) : List α := sortAsc (x :: h)

/-- The value `heappop(h)` returns: the smallest element (the sorted head). -/
def pyHeappopVal {α : Type} [Inhabited α] (h : List α) : α := h.headD default

/-- The heap left after `heappop(h)`: everything but the min. -/
def pyHeappopRest {α : Type} (h : List α) : List α := h.tail

/-- The value `heapreplace(h, x)` returns: the min *before* the replacement (ignores `x`). -/
def pyHeapreplaceVal {α : Type} [Inhabited α] (h : List α) (_x : α) : α := h.headD default

/-- The heap after `heapreplace(h, x)`: drop the min, then insert `x`. -/
def pyHeapreplaceRest {α : Type} [LinearOrder α] (h : List α) (x : α) : List α := sortAsc (x :: h.tail)

/-- `heapq.nsmallest(n, iterable)`: the `n` smallest elements, ascending. -/
def pyNsmallest {α β : Type} [PastaLean.PyIterable α β] [LinearOrder β] (n : Int) (xs : α) : List β :=
  (sortAsc (PastaLean.pyIter xs)).take n.toNat

/-- `heapq.nlargest(n, iterable)`: the `n` largest elements, descending. -/
def pyNlargest {α β : Type} [PastaLean.PyIterable α β] [LinearOrder β] (n : Int) (xs : α) : List β :=
  ((PastaLean.pyIter xs).mergeSort (fun a b => decide (b ≤ a))).take n.toNat

end Libraries.heapq
