Source<.Participant: Type>: Contract = (
    .get : (.self: &Participant) -> (.value: Int32) where {}
)

Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {

    }
)

State := (.resource: Resource)

Cell := (.state: &State)

implement Source<Cell> (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32) {
    value = self&.state&.resource.value
}

read_source := (.source: &Virtual<Source>) -> (.value: Int32) {
    value = get(source)
}

main := () -> () {
    state ::= State(Resource(42))
    cell ::= Cell(&state)
    source ::= to_virtual<Source>(&cell)
    deinit($&state.resource)
    read_source(&source)
}
