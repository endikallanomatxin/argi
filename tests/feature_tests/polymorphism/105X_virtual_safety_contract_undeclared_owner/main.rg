Factory#(.Participant: Type): Contract = (
    .make : (.self: &Participant) -> (.value: Errable#(Allocation, (..out_of_memory)))
    where depends_on(value, self)
)

Cell := (.allocator: $&Virtual#(Allocator))

implement Factory#(Cell) (.make = _impl_make_Cell)

_impl_make_Cell := (.self: &Cell) -> (.value: Errable#(Allocation, (..out_of_memory))) {

    value = allocate_bytes(self&.allocator, .size = 1, .alignment = 1)
}

main := (.system: System) -> () {

    backing ::= to_virtual#(Allocator)(system.page_allocator)
    cell ::= Cell($&backing)
    factory ::= to_virtual#(Factory)(&cell)
}
