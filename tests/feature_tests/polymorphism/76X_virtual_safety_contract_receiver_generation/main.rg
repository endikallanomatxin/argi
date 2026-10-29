Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant) -> (.value: Int32) where {}
)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

Cell := (.resource: Resource)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32) {
    value = self&.resource.value
}

read_source := (.source: &Virtual#(Source), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .value : Int32
) {
    assume error_tracer
    value = get(source)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    cell ::= Cell(Resource(42))
    source ::= to_virtual#(Source)(&cell)
    deinit($&cell.resource)
    read_source(&source)
}
