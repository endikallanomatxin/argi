Product#(.Result: Type): Contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Product#(.Unknown: Row, .Right: Column) = (.Result: Int32)
multiply(.left: &Row, .right: &Column) -> (.value: Int32) := {
    value = left&.value * right&.value
}
main() -> () := {}
