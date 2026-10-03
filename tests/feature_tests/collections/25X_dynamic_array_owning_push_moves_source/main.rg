Tracked : Type = (
    .allocation: Allocation
)

Tracked deinit(.self: $&Tracked) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    allocation_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocation_result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            value ::= Tracked(.allocation = ~payload)
            array ::= unwrap_or_abort(.value = DynamicArray#(.t: Tracked)(.capacity = 1))
            push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~value)
            deinit(.self = $&value)
            deinit#(.t: Tracked)(.self = $&array)
        }
    }
}
