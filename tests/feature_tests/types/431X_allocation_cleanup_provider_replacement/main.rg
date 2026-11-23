main := (.system: System) -> () {
    provider ::= CAllocator(.ffi = system.ffi)
    allocation ::= unwrap_or_abort(allocate_bytes(.self = $&provider, .size = 8))
    allocation._deallocator = Virtual#(Deallocator)($&provider)
}
