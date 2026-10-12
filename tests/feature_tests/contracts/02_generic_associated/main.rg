Source#(.item: Type): Contract = (
    get(.self: &Self) -> (.value: &item) where depends_on(value, self)
)

Cell#(.item: Type): Type = (.value: item)

Cell#(.item: Type) satisfies Source#(item)

get#(.item: Type)(.self: &Cell#(item)) -> (.value: &item) := {
    value = &self&.value
}

read#(.item: Type, .source_type: Type: Source#(item))(.source: &source_type) -> (.value: &item) := {
    value = get(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell#(Int32)(42)
    value ::= read#(Int32, Cell#(Int32))(&cell)
    if value&!= 42 { status_code = 1 }
}
