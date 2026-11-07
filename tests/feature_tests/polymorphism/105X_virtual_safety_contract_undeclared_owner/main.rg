Factory#(.Participant: Type): Contract = (
    .make : (.self: &Participant) -> (.value: Errable#(Allocation, (..out_of_memory)))
    where depends_on(value, self)
)

Cell := (.allocator: Virtual#(Allocator))

implement Factory#(Cell) (.make = _impl_make_Cell)

_impl_make_Cell := (.self: &Cell) -> (.value: Errable#(Allocation, (..out_of_memory))) {

    allocator ::= self&.allocator
    value = allocate_bytes($&allocator, .size = 1, .alignment = 1)
}

main := (.system: System) -> () {

    cell ::= Cell(system.page_allocator)
    factory ::= Virtual#(Factory)(&cell)
}
