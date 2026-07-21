# Python privacy mirrors what `from module import *` excludes: any underscore-prefixed name
# is private, EXCEPT dunders (`__x__`), which are the public protocol.
#   foo       -> public            __foo   -> private (strong / name-mangled)
#   _foo      -> private           __foo__ -> public  (dunder)
# Private names become Lean `private def`s (genuinely non-importable); names are otherwise
# preserved verbatim (`_foo` stays `_foo`).

def public_fn():
    return 1

def _single_underscore():
    return 2

def __double_underscore():
    return 3

def __dunder__():
    return 4

PUBLIC_CONST = 10
_secret = 20
