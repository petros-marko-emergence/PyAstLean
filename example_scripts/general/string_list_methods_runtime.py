def string_pipeline():
    s = "  Py Ast Lean  "
    trimmed = s.strip()
    lowered = trimmed.lower()
    parts = lowered.split()
    glued = "-".join(parts)
    return glued


def list_pipeline():
    xs = [3, 1]
    xs.append(2)
    xs.sort()
    count = len(xs)
    return xs, count
