Source#(.Participant: Type): Contract = (
    .item : Type

    domain storage
    .get   : (.self: &Participant) -> (.value: &item) where depends_on(value, self.storage)
    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
)

Cell := (.value: Int32, .other: Int32)

implement Source#(Cell) (.item: Type = Int32, .get = _impl_get_Cell, .reset = _impl_reset_Cell) where {
    storage(self.value)
}

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.value
}

_impl_reset_Cell := (.self: $&Cell) -> () {
    self&.value = 42
}

borrow := (.source: &Virtual#(Source#(Int32))) -> (.value: &Int32) {
    value = get(source)
}

reset_source := (.source: $&Virtual#(Source#(Int32))) -> () {
    reset(source)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source#(Int32))($&cell)
    before ::= borrow(&source)
    if before&!= 41 { status_code = 1 }
    reset_source($&source)
    after ::= borrow(&source)
    if after&!= 42 { status_code = 1 }
}
