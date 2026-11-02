Equal#(.Left: Type, .Right: Type): Contract = (
    .equal : (.left: Left, .right: Right) -> (.ok: Bool)
)

-- Borrowed scalar equality delegates to the existing scalar operation.
implement#(.Value: Type: _BuiltinEquality) Equal#(&Value, &Value) (
    .equal = (.left: &Value, .right: &Value) -> (.ok: Bool) {
        ok = left&== right&
    }
)
