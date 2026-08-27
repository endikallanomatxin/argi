Tracked : Type = (.id: Int32)

first_drops :: Int32 = 0
second_drops :: Int32 = 0
third_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 {
        first_drops = first_drops + 1
    }
    if self&.id == 2 {
        second_drops = second_drops + 1
    }
    if self&.id == 3 {
        third_drops = third_drops + 1
    }
}

store_wrapper(.slot: $&Tracked, .value: Tracked) -> () := {
    trusted_opaque_store_owned#(.t: Tracked)(.destination = slot, .source = ~value)
}

main(.system: System) -> (.status_code: Int32) := {
    slots_result ::= allocate(
        .self = system.allocator,
        .size = size_of(.type = Tracked) + size_of(.type = Tracked) + size_of(.type = Tracked),
    )
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            slots ::= ~payload
            first_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Tracked)(.base = slots.data).reference
            second_slot ::= mutable_reference_offset#(.t: Tracked)(.base = first_slot, .elements = 1).reference
            third_slot ::= mutable_reference_offset#(.t: Tracked)(.base = first_slot, .elements = 2).reference

            first :: Tracked = (.id = 1)
            second :: Tracked = (.id = 2)
            third :: Tracked = (.id = 3)
            store_wrapper(.slot = first_slot, .value = ~first)
            store_wrapper(.slot = second_slot, .value = ~second)
            store_wrapper(.slot = third_slot, .value = ~third)

            trusted_opaque_drop_owned#(.t: Tracked)(.slot = second_slot)
            trusted_opaque_drop_owned#(.t: Tracked)(.slot = first_slot)
            trusted_opaque_drop_owned#(.t: Tracked)(.slot = third_slot)
            deinit(.self = $&slots)

            if first_drops == 1 and second_drops == 1 and third_drops == 1 {
                status_code = 0
            } else {
                status_code = 2
            }
        }
    }
}
