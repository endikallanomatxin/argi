Readable#(.Value: Type): Contract = (
    .read : (.source: &Value) -> (.value: Int32)
)

Cell := (.value: Int32)

implement Readable#(Cell) ()

main := () -> () {}
