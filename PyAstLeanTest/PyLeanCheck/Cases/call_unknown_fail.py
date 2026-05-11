# PYASTLEANCHECK START
# TARGET: term
# EXIT: 1
# CHECK-ERR: callSyntax
# CHECK-ERR: Unknown identifier `[[F:[A-Za-z_][A-Za-z0-9_]*]]`
# PYASTLEANCHECK END

f(1, 2)
