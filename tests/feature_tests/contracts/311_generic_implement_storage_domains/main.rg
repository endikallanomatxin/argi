Source#(.Value: Type): Contract = (
    .storage: Region#(Value)
    .get : (.self: &Value) -> (.value: &Int32) where depends_on(value, self, self.storage)
)

Cell := #(.Tag: Type) (.storage: &Int32, .marker: Tag)

_get_cell := #(.Tag: Type) (.self: &Cell#(Tag)) -> (.value: &Int32) {
    value = self&.storage
}

implement#(.Tag: Type) Source#(Cell#(Tag)) (
    .storage = region(self.storage),
    .get = _get_cell)

main := (.system: System) -> (.status_code: Int32 = 0) {

    number :: Int32 = 42
    cell ::= Cell#(Int32)(.storage = &number, .marker = 1)
    if get(.self = &cell).value&!= 42 { status_code = 1 }
    erased ::= Virtual#(.contract: Source)(.value = &cell)
    if get(.self = &erased).value&!= 42 { status_code = 2 }
}
