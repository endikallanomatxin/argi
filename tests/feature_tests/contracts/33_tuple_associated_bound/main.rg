Capability: Contract = (
    .item: Type
)
Group#(.Left: Type, .Right: Type): Contract = (
    .Result: Type: Capability#(Left)
)
Row: Type = ()
Column: Type = ()
Row satisfies Capability#(Row)
implement Group#(Row, Column) (.Result: Type = Row)
main() -> () := {}
