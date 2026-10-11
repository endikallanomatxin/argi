Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = ()
Row: Type = ()
Column: Type = ()
satisfies Product#(Row, Column) = (.Result = 42)
main() -> () := {}
