Source: Abstract = (
    domain first
    domain second
    get(.self: &Self) -> (.value: &Int32) where depends_on(value, self.first)
)

State: Type = (.value: Int32)

Cell: Type = (.first: &State, .second: &State)

Cell implements Source where {
    first(self.first)
    second(self.second)
}

get(.self: &Cell) -> (.value: &Int32) := {
    value = &self&.first&.value
}

main() -> () := {
    state ::= State(42)
    cell ::= Cell(&state, &state)
    source ::= to_virtual#(Source)(&cell)
}
