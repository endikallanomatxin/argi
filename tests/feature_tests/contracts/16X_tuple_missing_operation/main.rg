Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

implement Product#(Row, Column) (.Result: Type = Int32)

main := () -> () {}
