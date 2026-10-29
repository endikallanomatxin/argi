main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = system.page_allocator, .size = 32, .alignment = 8)
    )
    original_size ::= allocation.size
    allocation.size = original_size + 8
    raw ::= raw_pointer#(.t: UIntNative)(.address = allocation.data.address + original_size).raw
    slot ::= trusted_establish_allocation_slot#(.t: UIntNative)(
        .allocation = &allocation, .slot = raw, .anchor = allocation.anchor
    ).reference
    deinit(.self = $&allocation)
}
