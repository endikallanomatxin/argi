Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

Other#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .other : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

implement Product#(Row, Column) (
    .Result   : Type = Other#(Row, Column).Result,
    .multiply = _multiply
)

implement Other#(Row, Column) (.Result: Type = Int32, .other = _other)

_other := (.left: &Row, .right: &Column) -> (.value: Int32) { value = 0 }

_multiply := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
    value = left&.value * right&.value
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}
