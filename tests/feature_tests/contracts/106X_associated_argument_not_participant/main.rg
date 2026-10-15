Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
implement Product#(.Left: Row, .Result: Int32) (.Result: Type = Int32)
main() -> () := {}
