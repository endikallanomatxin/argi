Reader#(.Participant: Type): Contract = ()

Cell: Type = ()

implement Reader#(Cell) ()

Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: Left, .right: Right) -> (.value: Result) where {}
)

implement Product#(Int32, Int64) (.Result: Type = Reader, .multiply = _impl_multiply_254)

_impl_multiply_254 := (.left: Int32, .right: Int64) -> (.value: Cell) { value = Cell() }

main := () -> () {}
