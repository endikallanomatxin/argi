Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
Row: Type = ()
Column: Type = ()
