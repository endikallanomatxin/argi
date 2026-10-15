Source#(.Value: Type): Contract = (
    domain storage
    .get: (.self: &Value) -> (.value: &Int32) where depends_on(value, self, self.storage)
)
Cell#(.Tag: Type): Type = (.storage: &Int32, .marker: Tag)
_get_cell#(.Tag: Type) := (.self: &Cell#(Tag)) -> (.value: &Int32) {
    value = self&.storage
}
implement#(.Tag: Type) Source#(Cell#(Tag)) (.get = _get_cell) where { storage(self.storage) }

main := (.system: System) -> (.status_code: Int32 = 0) {
    number :: Int32 = 42
    cell ::= Cell#(Int32)(.storage = &number, .marker = 1)
    if get(.self = &cell).value& != 42 { status_code = 1 }
    erased ::= to_virtual#(.contract: Source)(.value = &cell)
    if get(.self = &erased).value& != 42 { status_code = 2 }
}
