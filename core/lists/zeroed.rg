-- Constructs numeric zero values and fixed arrays of those values. This
-- operation cannot initialize references or arbitrary resource-bearing types.
zeroed#(.t: Type)() -> (.value: t) := {
    value = _zeroed(.type = t)
}
