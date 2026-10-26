Row := (.value: Int32)

Column := (.value: Int32)

Product<.Left: Type, .Right: Type>: Contract = (
    .Result   : Type
    .multiply : (.left: &Left, .right: &Right) -> (.result: Result)
)

OtherProduct<.Left: Type, .Right: Type>: Contract = (
    .Result   : Type
    .multiply : (.left: &Left, .right: &Right) -> (.result: Result)
)

multiply_row_column := (.left: &Row, .right: &Column) -> (.result: Int32) {
    result = left&.value * right&.value
}

add_row_column := (.left: &Row, .right: &Column) -> (.result: Int32) {
    result = left&.value + right&.value
}

implement Product<Row, Column> (
    .Result   : Type = Int32
    .multiply = multiply_row_column
)

implement OtherProduct<Row, Column> (
    .Result   : Type = Int32
    .multiply = add_row_column
)

product := <.A: Type, .B: Type> (.left: &A, .right: &B) -> (.result: Product<A, B>.Result) {
    result = Product<A, B>.multiply(left, right).result
}

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if product<Row, Column>(&row, &column).result != 42 { abort }
    if OtherProduct<Row, Column>.multiply(&row, &column).result != 13 { abort }
}
