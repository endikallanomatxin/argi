main() -> (.status_code: Int32) := {
    allocator_storage :: CAllocator = CAllocator()
    assume allocator ::= $&allocator_storage
    allocated ::= allocate(.self = $&allocator_storage, .size = 16)
    match allocated {
    ..error _ { status_code = 10 }
    ..ok ~ allocation {
    data ::= mutable_reinterpret_reference#(.from: UInt8, .to: Int32)(.base = allocation.data).reference
    values ::= trusted_array_view#(.t: Int32)(.data = data, .length = 4)

    set0 ::= set#(.t: Int32)(.self = $&values, .index = 0, .value = 3).result
    set1 ::= set#(.t: Int32)(.self = $&values, .index = 1, .value = 5).result
    set2 ::= set#(.t: Int32)(.self = $&values, .index = 2, .value = 7).result
    set3 ::= set#(.t: Int32)(.self = $&values, .index = 3, .value = 11).result
    if is(.value = set0, .variant = ..error) or is(.value = set1, .variant = ..error) or is(.value = set2, .variant = ..error) or is(.value = set3, .variant = ..error) {
        status_code = 11
        return
    }

    first_result ::= get#(.t: Int32)(.self = &values, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 12
        return
    }
    last_result ::= get#(.t: Int32)(.self = &values, .index = 3).result
    if is(.value = last_result, .variant = ..error) {
        status_code = 12
        return
    }

    if first_result..ok != 3 {
        status_code = 11
        return
    }

    if last_result..ok != 11 {
        status_code = 12
        return
    }

    second_result ::= get#(.t: Int32)(.self = &values, .index = 1).result
    if is(.value = second_result, .variant = ..error) {
        status_code = 13
        return
    }
    third_result ::= get#(.t: Int32)(.self = &values, .index = 2).result
    if is(.value = third_result, .variant = ..error) {
        status_code = 13
        return
    }
    status_code = second_result..ok + third_result..ok
    }
    }
}
