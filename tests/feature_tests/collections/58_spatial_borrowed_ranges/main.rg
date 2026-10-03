window(.array: $&DynamicArray#(.t: UIntNative), .start: UIntNative, .count: UIntNative) -> (.result: Errable#(.t: ArrayView#(.t: UIntNative), .reasons: (..out_of_bounds))) := {
    view ::= array_view#(.t: UIntNative)(.array = array).view
    result = slice#(.t: UIntNative)(.self = &view, .start = start, .count = count).result
}

exercise(.allocator: $&Allocator) -> (.status: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = allocator, .capacity = 8))
    empty ::= array_view#(.t: UIntNative)(.array = $&array).view
    if length#(.t: UIntNative)(.self = &empty).count != 0 { status = 1 }
    absent ::= get_ro_ref#(.t: UIntNative)(.self = &empty, .index = 0).result
    if is(.value = absent, .variant = ..error) == false { status = 2 }
    i :: UIntNative = 0
    while i < 4 {
        push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = i + 10)
        i = i + 1
    }
    view ::= unwrap_or_abort(.value = window(.array = $&array, .start = 1, .count = 2))
    if length#(.t: UIntNative)(.self = &view).count != 2 { status = 3 }
    unwrap_or_abort(.value = set#(.t: UIntNative)(.self = $&view, .index = 1, .value = 99).result)
    nested ::= unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = &view, .start = 1, .count = 1).result)
    observed ::= unwrap_or_abort(.value = get#(.t: UIntNative)(.self = &nested, .index = 0).result)
    if observed != 99 { status = 4 }
    readonly ::= array_view_ro#(.t: UIntNative)(.array = &array).view
    ro_window ::= unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = &readonly, .start = 2, .count = 1).result)
    ro_element ::= unwrap_or_abort(.value = get_ro_ref#(.t: UIntNative)(.self = &ro_window, .index = 0).result)
    if ro_element& != 99 { status = 5 }
    at_end ::= unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = &readonly, .start = 4, .count = 0).result)
    if length#(.t: UIntNative)(.self = &at_end).count != 0 { status = 6 }
    spare ::= get_ro_ref#(.t: UIntNative)(.self = &readonly, .index = 4).result
    if is(.value = spare, .variant = ..error) == false { status = 7 }
    invalid_start ::= slice#(.t: UIntNative)(.self = &readonly, .start = 5, .count = 0).result
    if is(.value = invalid_start, .variant = ..error) == false { status = 8 }
    huge :: UIntNative = 0
    huge = huge - 1
    invalid_count ::= slice#(.t: UIntNative)(.self = &readonly, .start = 1, .count = huge).result
    if is(.value = invalid_count, .variant = ..error) == false { status = 9 }
    invalid_huge_start ::= slice#(.t: UIntNative)(.self = &view, .start = huge, .count = 1).result
    if is(.value = invalid_huge_start, .variant = ..error) == false { status = 10 }
    removed ::= unwrap_or_abort(.value = pop#(.t: UIntNative)(.self = $&array).result)
    fresh ::= array_view#(.t: UIntNative)(.array = $&array).view
    if length#(.t: UIntNative)(.self = &fresh).count != 3 { status = 11 }
    if unwrap_or_abort(.value = get#(.t: UIntNative)(.self = &fresh, .index = 2).result) != 99 { status = 12 }
    deinit#(.t: UIntNative)(.allocator = allocator, .self = $&array)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    direct ::= exercise(.allocator = system.page_allocator).status
    if direct != 0 { status_code = direct }
    arena :: ArenaAllocator
    arena = unwrap_or_abort(.value = ArenaAllocator(.allocator = system.page_allocator))
    regional ::= exercise(.allocator = $&arena).status
    if regional != 0 { status_code = regional }
    reset(.self = $&arena)
    deinit(.self = $&arena)
}
