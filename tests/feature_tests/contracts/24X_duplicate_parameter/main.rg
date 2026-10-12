Product#(.Result: Type): Contract#(.Left: Type, .Result: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
main() -> () := {}
