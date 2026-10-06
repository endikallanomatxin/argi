escape(.allocator: $&Allocator) -> (.result: DynamicArray#(&Int32)) := {
    assume allocator
    array ::= unwrap_or_abort(DynamicArray#(&Int32)(.capacity = 1))
    local :: Int32 = 7

    push_assume_capacity($&array, &local)
    result = ~array
}

main(.system: System) -> () := {
    allocator ::= GeneralPurposeAllocator(system.page_allocator)
    escaped ::= escape($&allocator)
}
