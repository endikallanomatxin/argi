unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (.reference: $&UInt8)

old_root :: UInt8 = 7

Borrowing deinit(.self: $&Borrowing) -> () := {}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: UInt8) := {
    slot&.reference = reference
    result = 0
}

nested_store(.slot: $&Borrowing, .reference: $&UInt8) -> () := {
    value ::= store_and_return(.slot = slot, .reference = reference).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            target ::= ~payload
            holder ::= Borrowing(.reference = $&old_root)
            nested_store(.slot = $&holder, .reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
            deinit(.self = $&target)
            observed ::= holder.reference&
            status_code = 0
        }
    }
}
