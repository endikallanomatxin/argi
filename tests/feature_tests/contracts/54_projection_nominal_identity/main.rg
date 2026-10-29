Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Answer := (.value: Int32)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (.Result: Type = Answer, .multiply = _impl_multiply_289)

_impl_multiply_289 := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
    value = Answer(left&.value * right&.value)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    row ::= Row(6)
    column ::= Column(7)
    answer ::= multiply(&row, &column)
    if answer.value != 42 { abort }
}
