Source#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.value: Int32) where {}
)

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

Cell: Type = (.resource: Resource)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32)  {
    value = self&.resource.value
}

read_source(.source: &Virtual#(Source)) -> (.value: Int32) := {
    value = get(source)
}

main() -> () := {
    cell ::= Cell(Resource(42))
    source ::= to_virtual#(Source)(&cell)
    deinit($&cell.resource)
    read_source(&source)
}
