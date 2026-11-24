main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    provider ::= Virtual#(Deallocator)($&allocator)
    receipt ::= unwrap_or_abort(acquire_heap_storage(.size = 65, .alignment = 64, .ffi = system.ffi, .zeroed = true))
    storage ::= establish_allocation(.storage = ~receipt, .size = 65, .alignment = 64, .deallocator = provider)
    if storage.data.address % 64 != 0 { abort }
    last_raw ::= raw_pointer#(UInt8)(.address = storage.data.address + 64).raw
    first ::= trusted_establish_allocation_slot#(UInt8)(.allocation = &storage, .slot = storage.data, .anchor = storage.anchor)
    last ::= trusted_establish_allocation_slot#(UInt8)(.allocation = &storage, .slot = last_raw, .anchor = storage.anchor)
    if first& != 0 or last& != 0 { abort }
}
