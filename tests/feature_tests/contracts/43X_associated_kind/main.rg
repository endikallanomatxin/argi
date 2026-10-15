Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
implement Product#(Row, Column) (.Result: Int = 42)
main() -> () := {}
