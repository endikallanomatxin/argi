A : Type = (.value: UInt8, .to_b: $&UInt8)
B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    allocation_a ::= allocate_owned(.self = system.allocator, .size = 1)
    allocation_b ::= allocate_owned(.self = system.allocator, .size = 1)
    ref_a ::= allocation_a.data
    ref_b ::= allocation_b.data
    a :: A = (.value = 3, .to_b = ref_b)
    b :: B = (.value = 5, .to_a = ref_a)

    deinit(.self = $&allocation_a)
    status_code = 0
    if b.value != 5 {
        status_code = 1
    }
    if a.to_b& != 0 {
        status_code = 2
    }
    deinit(.self = $&allocation_b)
}
