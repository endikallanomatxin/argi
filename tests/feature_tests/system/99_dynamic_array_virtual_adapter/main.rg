create := (.allocator: $&Virtual#(Allocator)) -> (
    .result: Errable#(DynamicArray#(Int32), (..out_of_memory))
) {
    result = DynamicArray#(Int32)(.allocator = allocator, .capacity = 1)
}

grow := (
    .allocator: $&Virtual#(Allocator), .array: $&DynamicArray#(Int32)
) -> (.result: Errable#(Void, (..out_of_memory))) {
    result = ensure_capacity(.allocator = allocator, .self = array, .capacity = 64)
}

exercise := (.allocator: $&Virtual#(Allocator)) -> () {
    array ::= unwrap_or_abort(create(allocator))
    unwrap_or_abort(push(.allocator = allocator, .self = $&array, .value = 42))
    unwrap_or_abort(grow(.allocator = allocator, .array = $&array))
    if unwrap_or_abort(get_reference(&array, .index = 0))&!= 42 { abort }
    deinit($&array)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator ::= GeneralPurposeAllocator(system.page_allocator)
    allocator_virtual ::= to_virtual#(Allocator)($&allocator)
    exercise($&allocator_virtual)
    if has_live_allocations(&allocator).has_live { abort }

    arena ::= unwrap_or_abort(ArenaAllocator(.allocator = $&allocator_virtual, .block_size = 64))
    arena_virtual ::= to_virtual#(Allocator)($&arena)
    exercise($&arena_virtual)
    deinit($&arena)
    if has_live_allocations(&allocator).has_live { abort }
}
