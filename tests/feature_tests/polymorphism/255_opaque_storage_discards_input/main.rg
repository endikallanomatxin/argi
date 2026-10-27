Store#(.Participant: Type): Contract = (
    .put : (.self: &Participant, .storage: $&Allocation, .value: Tracked) -> () where retains(
        storage, value
    )
)

Tracked := (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

Cell: Type = ()

implement Store#(Cell) (.put = _impl_put_Cell)

_impl_put_Cell := (.self: &Cell, .storage: $&Allocation, .value: Tracked) -> () {
    discarded ::= ~value
}

main := (.system: System) -> () {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0
    storage ::= unwrap_or_abort(allocate_bytes(allocator, .size = 1))
    cell ::= Cell()
    erased ::= to_virtual#(Store)(&cell)
    put(&erased, $&storage, Tracked($&drops))
    if drops != 1 { abort }
}
