Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
satisfies Product#(.Left: Row, .Result: Int32) = (.Result: Int32)
main() -> () := {}
