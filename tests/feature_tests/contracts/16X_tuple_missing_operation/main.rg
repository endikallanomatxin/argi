Product#(.Result: Type): Contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Product#(Row, Column) = (.Result: Int32)
main() -> () := {}
