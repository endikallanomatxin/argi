main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = system.page_allocator, .block_size = 64)
    match initialized {
        ..error _ {
            status_code = 1
            return
        }
        ..ok ~constructed_value { arena = ~constructed_value }
    }
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = $&arena, .size = 32, .alignment = 8)
    )
    slot ::= allocation_slot#(.t: UIntNative)(.allocation = &allocation, .index = 0).slot
    reset(.self = $&arena)
    address ::= uninit_slot_address#(.t: UIntNative)(.slot = slot).address
    abort
}
