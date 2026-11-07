Source#(.Value: Type): Contract = (
    .first: Region#(Value)
    .second: Region#(Value)
    .get : (.self: &Value) -> (.value: &Int32) where depends_on(value, self.first)
)

State := (.value: Int32)

Cell := (.first: &State, .second: &State)

implement Source#(Cell) (
    .first = region(self.first),
    .second = region(self.second),
    .get = _source_get)

_source_get := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.first&.value
}

main := () -> () {
    state ::= State(42)
    cell ::= Cell(&state, &state)
    source ::= Virtual#(Source)(&cell)
}
