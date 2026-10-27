Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Self, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

main := () -> () {}
