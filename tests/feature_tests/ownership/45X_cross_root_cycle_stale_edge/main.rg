B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate_owned(.self = system.allocator, .size = 1)
    ref_a ::= allocation.data
    b :: B = (.value = 5, .to_a = ref_a)

    deinit(.self = $&allocation)
    if b.to_a& == 0 {
        status_code = 0
    }
}
