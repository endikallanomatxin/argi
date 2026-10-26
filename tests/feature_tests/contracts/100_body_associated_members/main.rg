Product<.Left: Type, .Right: Type>: Contract = (
    .Result   : Type
    .multiply : (.left: &Left, .right: &Right) -> (.value: Result)
    .Count    : Int
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product<.Right: Column, .Left: Row> (
    .Count    : Int  = 2,
    .Result   : Type = Int32,
    .multiply = _impl_multiply_286
)

_impl_multiply_286 := (.left: &Row, .right: &Column) -> (.value: Product<Row, Column>.Result) {
    value = left&.value * right&.value
}

Buffer := <.n: Int> (.values: Array<.n = n, .t: Int32>)

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
    buffer ::= Buffer<.n = Product<Row, Column>.Count>((20, 22))
    if buffer.values[0] + buffer.values[1] != 42 { abort }
}
