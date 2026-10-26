Source<.Value: Type>: Contract = (
    domain first
    domain second
    .get : (.self: &Value) -> (.value: &Int32) where depends_on(value, self.first)
)

State := (.value: Int32)

Cell := (.first: &State, .second: &State)

implement Source<Cell> (.get = _source_get) where {
    first(self.first)
    second(self.second)
}

_source_get := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.first&.value
}

main := () -> () {
    state ::= State(42)
    cell ::= Cell(&state, &state)
    source ::= to_virtual<Source>(&cell)
}
