Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_256)

_impl_multiply_256 := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> (.status_code: Int32 = 0) {

    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}
