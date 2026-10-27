Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type
    .Count  : Int

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (
    .Result   : Type = Int32,
    .Count    : Int  = 4,
    .multiply = _impl_multiply_284
)

_impl_multiply_284 := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Count) {
    value = left&.value * right&.value
}

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}
