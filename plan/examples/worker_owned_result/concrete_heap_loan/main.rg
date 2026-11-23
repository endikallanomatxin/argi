write := (.slot: $&UIntNative) -> () { slot& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    memory ::= unwrap_or_abort(allocate_bytes(.self = $&allocator, .size = 8, .alignment = 8))
    raw ::= raw_pointer#(.t: UIntNative)(.address = memory.data.address).raw
    reference ::= trusted_establish_allocation_slot#(.t: UIntNative)(.allocation = &memory, .slot = raw, .anchor = memory.anchor).reference
    reference& = 0
    alias ::= trusted_establish_allocation_slot#(.t: UIntNative)(.allocation = &memory, .slot = raw, .anchor = memory.anchor).reference
    task ::= unwrap_or_abort(async#(write)(.args = (.slot = reference), .executor = executor))
    _ = unwrap_or_abort(await($&task))
    if alias& != 42 { abort }
}
