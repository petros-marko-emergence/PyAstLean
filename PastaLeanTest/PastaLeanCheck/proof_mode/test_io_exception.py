# Test: IO exception handling (EOFError from input)
# CHECK: PyProofM
# CHECK: try
# CHECK: except
def main():
    try:
        x = input()
    except EOFError:
        x = "default"
    print(x)
