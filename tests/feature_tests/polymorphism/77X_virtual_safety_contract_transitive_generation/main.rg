Source: Abstract = (
    get(.self: &Self) -> (.value: Int32) where {}
)

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

State: Type = (.resource: Resource)

Cell: Type = (.state: &State)

Cell implements Source

get(.self: &Cell) -> (.value: Int32) := {
    value = self&.state&.resource.value
}

read_source(.source: &Virtual#(Source)) -> (.value: Int32) := {
    value = get(source)
}

main() -> () := {
    state ::= State(Resource(42))
    cell ::= Cell(&state)
    source ::= to_virtual#(Source)(&cell)
    deinit($&state.resource)
    read_source(&source)
}
