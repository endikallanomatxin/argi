Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant) -> (.value: Int32) where {}
)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

State := (.resource: Resource)

Cell := (.state: &State)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32) {
    value = self&.state&.resource.value
}

read_source := (.source: &Virtual#(Source), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .value : Int32
) {
    assume error_tracer
    value = get(source)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    state ::= State(Resource(42))
    cell ::= Cell(&state)
    source ::= to_virtual#(Source)(&cell)
    deinit($&state.resource)
    read_source(&source)
}
