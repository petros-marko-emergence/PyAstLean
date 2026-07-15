# Test: IO without explicit exception handling
# CHECK: PyProofM
# CHECK-NOT: try
def main():
    x = input()
    print(x)
