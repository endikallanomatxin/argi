Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
)
Row: Type = ()
Column: Type = ()
satisfies Product#(.Left: Row, .Left: Column) = (.Result: Int32)
main() -> () := {}
