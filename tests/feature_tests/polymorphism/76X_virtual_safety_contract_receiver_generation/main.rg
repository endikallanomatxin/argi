Source: Abstract = (
    get(.self: &Self) -> (.value: Int32) where {}
)

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

Cell: Type = (.resource: Resource)

Cell implements Source

get(.self: &Cell) -> (.value: Int32) := {
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
