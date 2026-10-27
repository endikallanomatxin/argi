Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (.multiply = _impl_multiply_234)

_impl_multiply_234 := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> () {}
