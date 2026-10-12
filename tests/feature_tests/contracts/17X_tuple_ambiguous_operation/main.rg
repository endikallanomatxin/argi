Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Product#(Row, Column) = (.Result: Int32)
multiply(.left: &Row, .right: &Column) -> (.value: Int32) := {
    value = left&.value * right&.value
}
multiply(.left: &Row, .right: &Column) -> (.value: Int64) := {
    value = 0
}
main() -> () := {}
