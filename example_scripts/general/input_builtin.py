def read_line():
    raw = input()
    return raw


def read_prompted():
    return input("n = ")


def read_nested_int():
    a = int(input())
    b = int(input())
    c = input()
    a += b
    return (a,c)


def echo_input():
    print(input())
    return 0

def input_inside_print():
    print(f"Enter a number: {int(input())}")
