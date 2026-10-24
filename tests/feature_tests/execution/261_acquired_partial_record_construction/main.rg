..stop

drops :: Int32 = 0

Resource: Type = (.id: Int32)

Pair: Type = (.left: Resource, .right: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

implement Deinit#(Pair) (
    .deinit = (.self: $&Pair) -> () { abort }
)

fail_when(.fail: Bool) -> (.result: Errable#(Int32, (..stop))) := {
    if fail { result = ..error(.reason = ..stop) } else { result = ..ok 42 }
}

build_partial(.fail: Bool, .ffi: $&ForeignFunctionInterface) -> (
    .result : Errable#(Int32, (..stop))
) := {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Pair)(.self = $&allocator))
    raw ::= raw_pointer#(.t: Pair)(.address = memory.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: Pair)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    #defer {
        trusted_opaque_drop(.slot = slot)
        trusted_opaque_mark_empty(.storage = $&memory)
    }
    slot&.left = Resource(.id = 42)
    if slot&.left.id != 42 { abort }
    value ::= fail_when(.fail = fail)!
    result = ..ok value
}

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    build_partial(.fail = true, .ffi = ffi) handle error {
        match error.reason { ..stop {} }
    }
    if drops != 42 { abort }
    build_partial(.fail = false, .ffi = ffi) handle error { abort }
    if drops != 84 { abort }
    status_code = 42
}
