Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
implement Product#(Row, Column, Int32) (.Result: Type = Int32)
main() -> () := {}
