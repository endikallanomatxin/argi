Source#(.Participant: Type): Contract = (
    .first: Region#(Participant)
    .second: Region#(Participant)
    .get : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.first)
)

State := (.value: Int32)

Cell := (.first: &State, .second: &State)

implement Source#(Cell) (
    .first = region(self.first),
    .second = region(self.second),
    .get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.first&.value
}

main := () -> () {
    state ::= State(42)
    cell ::= Cell(&state, &state)
    source ::= Virtual#(Source)(&cell)
}
