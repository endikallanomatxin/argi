Product<.Left: Type, .Right: Type>: Contract = (
    .Result   : Type
    .multiply : (.left: &Left, .right: &Right) -> (.value: Result)
)

Row := (.value: Int32)

Column := (.value: Int32)

_int_product := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = [left&.value * right&.value]
}

_wide_product := (.left: &Row, .right: &Column) -> (.value: Int64) { value = 0 }

implement Product<Row, Column> (.Result: Type = Int32, .multiply = _int_product)

implement Product<Row, Column> (.Result: Type = Int64, .multiply = _wide_product)

-- The associated result cannot distinguish two identical participant tuples.
main := () -> () {}
