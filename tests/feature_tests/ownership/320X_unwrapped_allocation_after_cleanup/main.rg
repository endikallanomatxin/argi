main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = system.page_allocator, .size = 3)
    )
    pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(
        .allocation = &allocation, .slot = allocation.data, .anchor = allocation.anchor
    ).reference
    pointer&= 97
    deinit(.self = $&allocation)
    observed ::= pointer&
}
