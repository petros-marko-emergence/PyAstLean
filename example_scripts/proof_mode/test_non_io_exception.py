# Test: Pure exception handling (no IO)
def divide(a, b):
    try:
        return a / b
    except:
        return 0
