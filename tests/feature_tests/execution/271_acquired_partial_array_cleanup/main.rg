..stop

drops :: Int32 = 0

Resource := (.id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

fail_when := (.fail: Bool) -> (.result: Errable#(Int32, (..stop))) {
    if fail { result = ..error(.reason = ..stop) } else { result = ..ok 42 }
}

build_partial := (.fail: Bool, .ffi: $&ForeignFunctionInterface) -> (
    .result: Errable#(Int32, (..stop))
) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: [3]Resource)(.self = $&allocator))
    raw ::= raw_pointer#(.t: [3]Resource)(.address = memory.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: [3]Resource)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    defer {
        trusted_opaque_drop(.slot = slot)
        trusted_opaque_mark_empty(.storage = $&memory)
    }
    index :: UIntNative = 0
    slot&[index] = Resource(.id = 10)
    index = 2
    slot&[index] = Resource(.id = 32)
    if slot&[0].id != 10 or slot&[2].id != 32 { abort }
    value ::= fail_when(.fail = fail)!
    result = ..ok value
}

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    build_partial(.fail = true, .ffi = ffi) handle error {
        match error.reason { ..stop {} }
    }
    if drops != 42 { abort }
    build_partial(.fail = false, .ffi = ffi) handle error { abort }
    if drops != 84 { abort }
    status_code = 42
}
