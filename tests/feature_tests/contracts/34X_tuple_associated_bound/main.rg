Capability#(.item: Type): contract = ()
Group#(.Result: Type: Capability#(Left)): contract#(.Left: Type, .Right: Type) = ()
Row: Type = ()
Column: Type = ()
Row satisfies Capability#(Column)
satisfies Group#(Row, Column) = (.Result: Row)
main() -> () := {}
