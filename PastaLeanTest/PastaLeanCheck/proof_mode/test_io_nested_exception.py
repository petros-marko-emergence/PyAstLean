# Test: Nested try-catch with IO
# CHECK: PyProofM
def main():
    try:
        x = int(input())
        try:
            y = 10 / x
        except:
            y = 0
        print(y)
    except:
        print("error")
