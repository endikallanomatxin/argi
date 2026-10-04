main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: &Int32)(.capacity = 4))
    i :: Int32 = 0
    while i < 4 {
        local ::= i
        push_assume_capacity#(.t: &Int32)(.self = $&array, .value = &local)
        i = i + 1
    }
    reference ::= unwrap_or_abort(.value = get_ro_ref#(.t: &Int32)(.self = &array, .index = 0))
    status_code = reference&&
}
