import random
import functools
import collections
import string
import math
import datetime
from typing import *
from functools import *
from collections import *
from itertools import *
from heapq import *
from bisect import *
from string import *
from operator import *
from math import *

def maxWidthOfVerticalArea(points: List[List[int]]) -> int:
    points.sort()
    return max((b[0] - a[0] for a, b in pairwise(points)))
