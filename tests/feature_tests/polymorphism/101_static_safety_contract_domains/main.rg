Source#(.Participant: Type): Contract = (
    domain storage
    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
)

Cell := (.value: Int32, .other: Int32)

implement Source#(Cell) (.get = _impl_get_Cell, .reset = _impl_reset_Cell) where {
    storage(self.value)
}

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.value
}

_impl_reset_Cell := (.self: $&Cell) -> () {
    self&.value = 42
}

borrow := #(.source_type: Type: Source) (.source: &source_type) -> (.value: &Int32) {

    value = get(source)
}

main := () -> (.status_code: Int32 = 0) {

    cell ::= Cell(41, 9)
    before ::= borrow(&cell)
    if before&!= 41 { status_code = 1 }
    reset($&cell)
    after ::= borrow(&cell)
    if after&!= 42 { status_code = 1 }
}
