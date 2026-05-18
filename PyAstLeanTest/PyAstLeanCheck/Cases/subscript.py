# PYASTLEANCHECK START
# TARGET: command
# CHECK: def arr := [(1 : Int), (2 : Int), (3 : Int)]
# CHECK: def result := GetElem.getElem arr (0 : Int)
# PYASTLEANCHECK END

arr = [1, 2, 3]
result = arr[0]
