Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = ()
Row: Type = ()
Column: Type = ()
satisfies Product#(.Left: Row, .Left: Column) = (.Result: Int32)
main() -> () := {}
