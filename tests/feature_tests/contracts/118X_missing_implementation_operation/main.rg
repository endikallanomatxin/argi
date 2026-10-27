Cell := (.value: Int32)

Reader#(.T: Type): Contract = (
    .Result : Type
    .read   : (.value: &T) -> (.result: Result)
)

implement Reader#(Cell) (.Result: Type = Int32)

main := () -> () {}
