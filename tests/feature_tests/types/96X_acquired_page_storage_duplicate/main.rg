main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
        .value = system.memory
    )
    storage ::= unwrap_or_abort(
        .value = acquire_page_storage(.memory = system.memory, .size = 8, .alignment = 8192)
    )
    first ::= establish_allocation(
        .storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    second ::= establish_allocation(
        .storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    deinit(.self = $&first)
    deinit(.self = $&second)
}
