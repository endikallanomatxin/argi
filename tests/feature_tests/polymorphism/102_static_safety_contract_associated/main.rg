Source#(.Participant: Type): Contract = (
    .item : Type
    .get  : (.self: &Participant) -> (.value: &item) where depends_on(value, self)
)

Cell := #(.item: Type) (.value: item)

implement#(.item: Type) Source#(Cell#(item)) (.item: Type = item, .get = _cell_get)

_cell_get := #(.item: Type) (.self: &Cell#(item)) -> (.value: &item) {
    value = &self&.value
}

read := #(.item: Type, .source_type: Type: Source#(.item: item)) (.source: &source_type) -> (
    .value : &item
) {

    value = get(source)
}

main := () -> (.status_code: Int32 = 0) {

    cell ::= Cell#(Int32)(42)
    value ::= read#(Int32, Cell#(Int32))(&cell)
    if value&!= 42 { status_code = 1 }
}
