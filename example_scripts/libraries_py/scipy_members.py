from scipy.special import comb, factorial, gamma
from scipy import constants
from scipy.stats import gmean
from scipy.linalg import det, norm


def demo():
    a = factorial(5)
    b = comb(6, 2)
    g = gamma(5.0)
    p = constants.pi
    m = gmean([1.0, 4.0, 16.0])
    d = det([[1.0, 2.0], [3.0, 4.0]])
    n = norm([3.0, 4.0])
    return a
