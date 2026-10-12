Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
satisfies Product#(Row, Column) = (.Result = 42)
main() -> () := {}
