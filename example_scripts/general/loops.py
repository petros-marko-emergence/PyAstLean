def nested_loops(n):
    total = 0
    for i in range(n):
        for j in range(i):
            total += j
    return total

def super_nested_loops(n):
    res = 0
    for i in range(n):
        for j in range(n):
            for k in range(n):
                for l in range(n):
                    res += i + j + k + l
    return res

def while_in_for(n):
    count = 0
    for i in range(n):
        j = i
        while j > 0:
            count += 1
            j -= 1
    return count

def breakable_loop(n):
    total = 0
    for i in range(n):
        if i == 5:
            break
        total += i
    j = 0
    while j < n:
        if j <= 3:
            continue
        total += j
        j += 1
 
    return total
