# Test: Try-finally with IO
# CHECK: PyProofM
# CHECK: try
# CHECK: finally
def main():
    try:
        x = input()
    finally:
        print("cleanup")
