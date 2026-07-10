from typing import (
    Any,
    Optional,
    Type,
    TypeVar,
)

T = TypeVar("T")
V = TypeVar("V")

CONTRACT_FUNCS = [
    "Requires",
    "Ensures",
    "Exsures",
    "Invariant",
    "Decreases",
    "Assume",
    "Assert",
    "Refute",
    "Result",
    "ResultT",
    "Implies",
    "Forall",
    "Unfold",
    "isNaN",
    "Reveal",
]


def _check_bool(expr: bool) -> bool:
    """Validate a contract condition at runtime and return it unchanged."""
    assert expr
    return expr

def Requires(expr: bool) -> bool:
    return _check_bool(expr)

def Ensures(expr: bool) -> bool:
    return _check_bool(expr)

def Exsures(exception: type, expr: bool) -> bool:
    return _check_bool(expr)

def Invariant(expr: bool) -> bool:
    return _check_bool(expr)


def Decreases(expr: Optional[int], condition: bool = True) -> bool:
    if condition:
        return _check_bool(expr is not None)
    return True


def Assume(expr: bool) -> None:
    _check_bool(expr)


def Assert(expr: bool) -> bool:
    return _check_bool(expr)


def Refute(expr: bool) -> bool:
    return _check_bool(not expr)

def Result() -> Any:
    return None

def ResultT(value: V) -> V:
    """
    Like Result() but explicitly typed to avoid Any types.
    """
    return value


def Implies(lhs: bool, rhs: bool) -> bool:
    return (not lhs) or rhs


def Forall(*_args: Any, **_kwargs: Any) -> bool:
    return True


def Unfold(expr: T) -> T:
    return expr


def isNaN(expr: float) -> bool:
    return expr != expr


def Reveal(expr: T) -> T:
    return expr
