Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product<Row, Column> (.Result: Type = Int64, .multiply = _impl_multiply_253)

_impl_multiply_253 := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> () {}
