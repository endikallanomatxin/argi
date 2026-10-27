Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(.Unknown: Row, .Right: Column) (
    .Result   : Type = Int32,
    .multiply = _impl_multiply_271
)

_impl_multiply_271 := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> () {}
