main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    first_push ::= push#(.t: Int32)(.self = $&array, .value = 10)
    if is(.value = first_push, .variant = ..error) {
        status_code = 1
        return
    }

    old_alias_result ::= get_ro_ref(.self = &array, .index = 0).result
    if is(.value = old_alias_result, .variant = ..error) {
        status_code = 3
        return
    }
    old_alias ::= old_alias_result..ok
    second_push ::= push#(.t: Int32)(.self = $&array, .value = 20)
    if is(.value = second_push, .variant = ..error) {
        status_code = 2
        return
    }

    status_code = old_alias&
    deinit#(.t: Int32)(.self = $&array)
}
