Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product<.Left = 3, .Right: Column> (.Result: Type = Int32, .multiply = multiply)

multiply := (.left: &Row, .right: &Column) -> (.value: Int32) {
    value = left&.value * right&.value
}

main := () -> () {}
