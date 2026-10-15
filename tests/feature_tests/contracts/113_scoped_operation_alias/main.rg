Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)

OtherProduct#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)

multiply_row_column := (.left: &Row, .right: &Column) -> (.result: Int32) {
    result = left&.value * right&.value
}

add_row_column := (.left: &Row, .right: &Column) -> (.result: Int32) {
    result = left&.value + right&.value
}

implement Product#(Row, Column) (
    .Result: Type = Int32
    .multiply = multiply_row_column
)

implement OtherProduct#(Row, Column) (
    .Result: Type = Int32
    .multiply = add_row_column
)

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if Product#(Row, Column).multiply(&row, &column).result != 42 { abort }
    if OtherProduct#(Row, Column).multiply(&row, &column).result != 13 { abort }
}
