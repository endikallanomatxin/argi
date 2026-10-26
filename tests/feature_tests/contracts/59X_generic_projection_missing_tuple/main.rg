Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product<Row, Column> (.Result: Type = Int32, .multiply = _impl_multiply_256)

_impl_multiply_256 := (.left: &Row, .right: &Column) -> (.value: Product<Row, Column>.Result) {
    value = left&.value * right&.value
}

product := <.A: Type, .B: Type> (.left: &A, .right: &B) -> (.value: Product<B, A>.Result) {
    value = multiply(left, right).value
}

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if product(&row, &column).value != 42 { abort }
}
