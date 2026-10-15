-- Constructs numeric zeros, null C callbacks, and fixed arrays of those values.
-- This cannot initialize safe references or arbitrary resource-bearing types.
zeroed#(.t: Type)() -> (.value: t) := {
    value = _zeroed(.type = t)
}
