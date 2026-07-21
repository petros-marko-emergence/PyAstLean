# `list.pop()` removes and returns the last element; `list.pop(i)` the element at index i.
# Both lower to a value read (`pyPopValue`) plus a container update (`pyPopRest`), since the
# runtime containers are immutable values. `pop` mutates its receiver, so the function body is
# threaded monadically (`Id.run do`) with the container bound `let mut`.

def list_pop_last():
    xs = [10, 20, 30, 40]
    last = xs.pop()
    return last

def list_pop_index():
    ys = [10, 20, 30, 40]
    first = ys.pop(0)
    return first

# Sets are modelled as deduplicated lists; `set.pop()` removes an arbitrary element.
def set_pop():
    seen = set([1, 2, 3])
    seen.discard(2)
    x = seen.pop()
    return x
