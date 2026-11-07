exercise := (.allocator: Virtual#(Allocator)) -> () {
    assume allocator

    strings ::= unwrap_or_abort(DynamicArray#(String)(.capacity = 1))
    index :: UIntNative = 0
    while index < 40 {
        text ::= unwrap_or_abort(String(.length = 1))
        unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
        unwrap_or_abort(push(.self = $&strings, .value = ~text))
        index = index + 1
    }
    duplicate ::= unwrap_or_abort(copy(.self = &strings, .allocator = allocator))
    if length(&duplicate).count != 40 { abort }
    first ::= unwrap_or_abort(get_reference(&duplicate, .index = 0))
    if unwrap_or_abort(bytes_get(.view = first, .index = 0)) != 65 { abort }

    map ::= unwrap_or_abort(HashMap#(Int32, Int32)())
    key :: Int32 = 0
    while key < 40 {
        unwrap_or_abort(put(.self = $&map, .key = key, .value = key * 3))
        key = key + 1
    }
    match get(.self = &map, .key = &7).result {
        ..none { abort }
        ..some entry { if entry.value != 21 { abort } }
    }

    -- A virtual provider can back another allocator without changing callers.
    arena ::= unwrap_or_abort(ArenaAllocator(.allocator = allocator, .block_size = 64))
    arena_handle ::= Virtual#(Allocator)($&arena)
    nested ::= GeneralPurposeAllocator(.allocator = arena_handle)
    nested_handle ::= Virtual#(Allocator)($&nested)
    allocation ::= unwrap_or_abort(allocate#(UInt32)($&nested_handle, .count = 8))
    if allocation.size != 32 { abort }
    deinit($&allocation)
    if has_live_allocations(&nested).has_live { abort }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    -- Both pipe temporaries must survive every allocation made in this scope.
    assume allocator := GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    exercise(allocator)

    storage ::= GeneralPurposeAllocator(system.page_allocator)
    handle ::= Virtual#(Allocator)($&storage)
    exercise(handle)
    if has_live_allocations(&storage).has_live { abort }

    -- Growth can select a different provider; Allocation keeps its own cleanup.
    array ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
    unwrap_or_abort(push(.self = $&array, .value = 42))
    unwrap_or_abort(ensure_capacity(.self = $&array, .capacity = 100, .allocator = handle))
    if unwrap_or_abort(get_reference(&array, .index = 0))&!= 42 { abort }
    deinit($&array)
    if has_live_allocations(&storage).has_live { abort }
}
