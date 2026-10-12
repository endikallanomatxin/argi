Product#(.Result: Type): Contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Answer: Type = (.value: Int32)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

satisfies Product#(Row, Column) = (.Result: Answer)

multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) := {
    value = Answer(left&.value * right&.value)
}

main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    answer ::= multiply(&row, &column)
    if answer.value != 42 { abort }
}
