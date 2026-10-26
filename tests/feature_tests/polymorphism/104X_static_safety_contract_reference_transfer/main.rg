Mover<.Participant: Type>: Contract = (
    .move : (.self: &Participant, .input: &Int32) -> (.value: &Int32) where transfers(
        value, input
    )
)

Cell := (.value: Int32)

implement Mover<Cell> (.move = _impl_move_Cell)

_impl_move_Cell := (.self: &Cell, .input: &Int32) -> (.value: &Int32) {
    value = ~input
}

main := () -> () {}
