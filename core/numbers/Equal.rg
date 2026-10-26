Equal<.Left: Type, .Right: Type, .Args: Type>: Contract = (
    .equal : (.args: Args) -> (.ok: Bool)
)

-- Borrowed scalar equality delegates to the existing scalar operation.
implement<.Value: Type: _BuiltinEquality> Equal<Value, Value, (.left: &Value, .right: &Value)> (
    .equal = (.args: (.left: &Value, .right: &Value)) -> (.ok: Bool) {
        ok = args.left&== args.right&
    }
)
