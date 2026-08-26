B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    ref_a ::= allocation.data
    b :: B = (.value = 5, .to_a = ref_a)

    deinit(.self = $&allocation)
    if b.to_a& == 0 {
        status_code = 0
    }
    }
    }
}
