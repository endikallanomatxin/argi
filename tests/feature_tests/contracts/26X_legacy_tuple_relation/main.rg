Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
Row satisfies Product#(Int32)
main() -> () := {}
