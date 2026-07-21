# Bare top-level `for`/`if`/`while` are not executable in Lean, so we thread the names
# each block mutates as state: the block becomes a value returning the updated names,
# which are then re-exported as fresh `def`s. Names assigned once before a block are
# versioned (`x₀`) so the clean name (`x`) holds the block's result, and each result def
# is named after a short position-based hash so distinct blocks never collide.
#
# A standalone `def main()` (with no `__main__` guard) is renamed to `main'` in Lean, since
# Lean reserves the top-level name `main` for the program entry point (which must have type
# `IO (UInt32 | Unit | PUnit)`). Here it is just a normal helper, so it yields the name.

def main():
    return "hi"

# for: single-variable fold
x = 0
for i in range(5):
    x += i

# if: swap two globals (native tuple unpacking lowers through Prod.fst/snd)
AX = 3
BX = 2
if AX > BX:
    AX, BX = BX, AX

# while: thread two globals through one Id.run block
total = 0
i = 0
while i < 5:
    total += i
    i += 1
