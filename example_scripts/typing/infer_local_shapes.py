# A captured local's type is read off its literal shape (TypeInfer.ofValue), so the lifted helper
# gets a typed parameter Lean can resolve; an unannotated class field is typed the same way.
class Counter:
    def __init__(self, n: int):
        self.c = [0] * n
        self.tag = "x"


def solve(n: int) -> int:
    grid = [0] * n

    def go(i: int) -> int:
        if i >= n:
            return 0
        return grid[i] + go(i + 1)

    return go(0)


def main():
    print(solve(3))


if __name__ == "__main__":
    main()
