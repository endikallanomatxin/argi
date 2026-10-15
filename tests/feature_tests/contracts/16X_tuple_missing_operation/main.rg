Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    .multiply: (.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
implement Product#(Row, Column) (.Result: Type = Int32)
main() -> () := {}
