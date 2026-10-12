Capability: Contract = (
    .item: Type
)
Group#(.Left: Type, .Right: Type): Contract = (
    .Result: Type: Capability#(Left)
)
Row: Type = ()
Column: Type = ()
Row satisfies Capability#(Column)
satisfies Group#(Row, Column) = (.Result: Row)
main() -> () := {}
