Source#(.Participant: Type): Contract = (
    .storage: Region#(Participant)
    .sibling: Region#(Participant)
    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
)

Cell := (.value: Int32, .other: Int32)

implement Source#(Cell) (
    .storage = region(self.value),
    .sibling = region(self.other),
    .get = _impl_get_Cell, .reset = _impl_reset_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
    value = &self&.value
}

_impl_reset_Cell := (.self: $&Cell) -> () {
    self&.value = 42
}

borrow := (.source: &Virtual#(Source)) -> (.value: &Int32) {

    value = get(source)
}

reset_source := (.source: $&Virtual#(Source)) -> () {
    reset(source)
}

main := () -> (.status_code: Int32 = 0) {

    cell ::= Cell(41, 9)
    source ::= Virtual#(Source)($&cell)
    independent ::= &cell.other
    before ::= borrow(&source)
    if before&!= 41 { status_code = 1 }
    reset_source($&source)
    if independent&!= 9 { status_code = 1 }
    after ::= borrow(&source)
    if after&!= 42 { status_code = 1 }
}
