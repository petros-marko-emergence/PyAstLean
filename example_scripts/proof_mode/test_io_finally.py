# Test: Try-finally with IO
def main():
    try:
        x = input()
    finally:
        print("cleanup")
