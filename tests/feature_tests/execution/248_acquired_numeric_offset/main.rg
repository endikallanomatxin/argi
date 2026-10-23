Pair: Type = (.value: Int32, .fraction: Float32)

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate#(.t: Int32)(.self = $&allocator, .count = 2)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            raw ::= raw_pointer#(.t: Int32)(.address = memory.data.address).raw
            first ::= trusted_establish_allocation_slot#(.t: Int32)(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 0)
            ).reference
            second ::= trusted_mutable_reference_offset(.base = first, .elements = 1).reference
            second&= 42
            status_code = second&
        }
    }
    aggregate ::= allocate#(.t: Pair)(.self = $&allocator, .count = 2)
    match aggregate {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            raw ::= raw_pointer#(.t: Pair)(.address = memory.data.address).raw
            first ::= trusted_establish_allocation_slot#(.t: Pair)(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 0)
            ).reference
            second ::= trusted_mutable_reference_offset(.base = first, .elements = 1).reference
            second&= (.value = 42, .fraction = 0.5)
            readonly ::= read_reference(.base = first).reference
            selected ::= trusted_reference_offset(.base = readonly, .elements = 1).reference
            if selected&.value != 42 or selected&.fraction != 0.5 { abort }
        }
    }
}
