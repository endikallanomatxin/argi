Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    multiply(.left: &Self, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
main() -> () := {}
