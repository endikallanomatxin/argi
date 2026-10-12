Capability#(.item: Type): Contract = ()
Group#(.Result: Type: Capability#(Left)): Contract#(.Left: Type, .Right: Type) = ()
Row: Type = ()
Column: Type = ()
Row satisfies Capability#(Row)
satisfies Group#(Row, Column) = (.Result: Row)
main() -> () := {}
