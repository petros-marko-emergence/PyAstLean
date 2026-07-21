# Test: IO exception handling (EOFError from input)
def main():
    try:
        x = input()
    except EOFError:
        x = "default"
    print(x)
