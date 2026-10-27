Source#(.Participant: Type): Contract = (
    domain storage
    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell, .reset = _impl_reset_Cell) where {
    storage(self.value)
}

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) { value = &self&.value }

_impl_reset_Cell := (.self: $&Cell) -> () { self&.value = 42 }

Relay#(.Participant: Type): Contract = (
    .forward : (.self: &Participant, .source: $&Virtual#(Source)) -> (.value: $&Virtual#(Source))
    where refers_to(value, source)
)

RelayCell := (.unused: Int32)

implement Relay#(RelayCell) (.forward = _impl_forward_RelayCell)

_impl_forward_RelayCell := (.self: &RelayCell, .source: $&Virtual#(Source)) -> (
    .value : $&Virtual#(Source)
) {
    value = source
}

forward_again := (.relay: &Virtual#(Relay), .source: $&Virtual#(Source)) -> (
    .value : $&Virtual#(Source)
) {
    value = forward(relay, source)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(41)
    relay_cell ::= RelayCell(0)
    relay ::= to_virtual#(Relay)(&relay_cell)
    source ::= to_virtual#(Source)($&cell)
    forwarded ::= forward_again(&relay, $&source)
    old ::= get(forwarded)
    if old&!= 41 { status_code = 1 }
    reset(forwarded)
    current ::= get(forwarded)
    if current&!= 42 { status_code = 1 }

}
