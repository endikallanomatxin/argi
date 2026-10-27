Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_319)

implement Product#(.Right: Column, .Left: Row) (
    .Result   : Type = Int64,
    .multiply = _impl_multiply_319
)

_impl_multiply_319 := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> () {}
