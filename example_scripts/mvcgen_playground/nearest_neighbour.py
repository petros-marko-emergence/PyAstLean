from contracts import *
import math


def euclidean_distance(p1: list[int], p2: list[int]) -> float:
    # Precondition: the two points live in the same number of dimensions.
    Requires(len(p1) == len(p2))
    if len(p1) != len(p2):
        raise ValueError("Points must have the same number of dimensions")
    # Past the guard the dimensions must match (provable from the precondition).
    Assert(len(p1) == len(p2))
    # Using zip, a list comprehension, and math.pow
    sq_diffs = [math.pow(a - b, 2) for a, b in zip(p1, p2)]
    return math.sqrt(sum(sq_diffs))


def find_nearest_neighbor(target: list[int], dataset: list[list[int]]):
    # Precondition: there is at least one candidate point to compare against.
    Requires(len(dataset) > 0)
    try:
        # Distances to every point via a list comprehension over a raising function
        distances = [euclidean_distance(target, point) for point in dataset]
        min_dist = min(distances)
        # The minimum is one of the computed distances.
        Assert(min_dist in distances)
        # Find the index of the minimum distance with an explicit loop + break
        min_index = -1
        for i, d in enumerate(distances):
            # The index stays within bounds for the whole scan.
            Invariant(min_index < len(distances))
            if d == min_dist:
                min_index = i
                break
        return (min_dist, dataset[min_index])
    except ValueError:
        # Fallback when a point has the wrong number of dimensions
        return (-1.0, [])
