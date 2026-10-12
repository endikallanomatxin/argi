Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

Other#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    other(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
satisfies Product#(Row, Column) = (.Result: Other#(Row, Column).Result)
satisfies Other#(Row, Column) = (.Result: Int32)
other(.left: &Row, .right: &Column) -> (.value: Int32) := { value = 0 }

multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) := {
    value = left&.value * right&.value
}

main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}
