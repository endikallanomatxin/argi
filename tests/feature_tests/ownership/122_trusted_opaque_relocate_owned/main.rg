Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0
third_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    if self&.id == 3 { third_drops = third_drops + 1 }
    deinit(.self = $&self&.allocation)
}

make_tracked(.allocator: $&Allocator, .id: Int32) -> (.result: Errable#(.t: Tracked, .reasons: (..out_of_memory))) := {
    allocation_result ::= allocate(.self = allocator, .size = 1)
    match allocation_result {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            value ::= Tracked(.id = id, .allocation = ~payload)
            result = ..ok ~value
        }
    }
}

main(.system: System) -> (.status_code: Int32) := {
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = Tracked) * 8)
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            base ::= mutable_reinterpret_reference#(.from: UInt8, .to: Tracked)(.base = slots.data).reference
            a ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 0).reference
            b ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 1).reference
            c ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 2).reference
            d ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 3).reference
            e ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 4).reference
            f ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 5).reference
            g ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 6).reference
            h ::= mutable_reference_offset#(.t: Tracked)(.base = base, .elements = 7).reference

            first_result ::= make_tracked(.allocator = system.allocator, .id = 1)
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    second_result ::= make_tracked(.allocator = system.allocator, .id = 2)
                    match second_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ second_payload {
                            third_result ::= make_tracked(.allocator = system.allocator, .id = 3)
                            match third_result {
                                ..error _ { status_code = 4 }
                                ..ok ~ third_payload {
                                    trusted_opaque_store(.destination = a, .source = ~first_payload)
                                    trusted_opaque_store(.destination = e, .source = ~second_payload)
                                    trusted_opaque_store(.destination = g, .source = ~third_payload)

                                    trusted_opaque_relocate(.source = a, .destination = b)
                                    trusted_opaque_relocate(.source = b, .destination = c)
                                    trusted_opaque_relocate(.source = c, .destination = d)
                                    trusted_opaque_relocate(.source = e, .destination = f)
                                    trusted_opaque_relocate(.source = g, .destination = h)

                                    if first_drops != 0 or second_drops != 0 or third_drops != 0 {
                                        status_code = 5
                                        return
                                    }

                                    trusted_opaque_drop(.slot = d)
                                    trusted_opaque_drop(.slot = f)
                                    trusted_opaque_drop(.slot = h)
                                    deinit(.self = $&slots)

                                    if first_drops == 1 and second_drops == 1 and third_drops == 1 {
                                        status_code = 0
                                    } else {
                                        status_code = 6
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
