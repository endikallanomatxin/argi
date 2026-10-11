Store: Abstract = (
    put(.self: &Self, .storage: $&Allocation, .value: Tracked) -> () where retains(storage, value)
)

Tracked: Type = (.drops: $&Int32)

Tracked deinit(.self: $&Tracked) -> () := { self&.drops&= self&.drops&+ 1 }

Cell: Type = ()

Cell implements Store

put(.self: &Cell, .storage: $&Allocation, .value: Tracked) -> () := {
    discarded ::= ~value
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0
    storage ::= unwrap_or_abort(allocate(allocator, .size = 1))
    cell ::= Cell()
    erased ::= to_virtual#(Store)(&cell)
    put(&erased, $&storage, Tracked($&drops))
    if drops != 1 { abort }
}
