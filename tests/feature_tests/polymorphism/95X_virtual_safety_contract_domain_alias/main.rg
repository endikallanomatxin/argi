Source<.Participant: Type>: Contract = (
    domain first
    domain second
    .get : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.first)
)

State := (.value: Int32)

Cell := (.first: &State, .second: &State)

implement Source<Cell> (.get = _impl_get_Cell) where {
    first(self.first)
    second(self.second)
}

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.first&.value
}

main := () -> () {
    state ::= State(42)
    cell ::= Cell(&state, &state)
    source ::= to_virtual<Source>(&cell)
}
