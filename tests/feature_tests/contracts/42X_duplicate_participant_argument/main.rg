Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type
)

Row: Type = ()

Column: Type = ()

implement Product#(.Left: Row, .Left: Column) (.Result: Type = Int32)

main := () -> () {}
