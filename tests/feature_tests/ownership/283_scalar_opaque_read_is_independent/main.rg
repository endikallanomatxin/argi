main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    source ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.capacity = 1))
    destination ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.capacity = 1))

    push#(.t: UIntNative)(.self = $&source, .value = 7)
    value_result ::= get(.self = &source, .index = 0).result
    if is(.value = value_result, .variant = ..error) {
        status_code = 1
        return
    }
    value ::= value_result..ok
    push#(.t: UIntNative)(.self = $&destination, .value = value)

    deinit#(.t: UIntNative)(.self = $&source)
    destination_result ::= get(.self = &destination, .index = 0).result
    if is(.value = destination_result, .variant = ..error) {
        status_code = 2
        return
    }
    if destination_result..ok != 7 {
        deinit#(.t: UIntNative)(.self = $&destination)
        status_code = 1
        return
    }

    deinit#(.t: UIntNative)(.self = $&destination)
    status_code = 0
}
