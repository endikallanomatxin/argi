Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
Row: Type = ()
Column: Type = ()
