main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    arr ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    defer deinit(.self = $&arr)

    push(.self = $&arr, .value = 10, .allocator = allocator)
    push(.self = $&arr, .value = 20, .allocator = allocator)

    copied_result ::= FalliblyCopyable#(
        DynamicArray#(Int32)
    ).copy(.self = &arr, .allocator = allocator)
    if is(.value = copied_result, .variant = ..error) {
        status_code = 5
        return
    }
    copied ::= ~copied_result ..ok
    defer deinit(.self = $&copied)

    set_result ::= replace(
        .self = $&copied, .index = 0, .value = 99, .allocator = allocator
    ).result
    if is(.value = set_result, .variant = ..error) {
        status_code = 6
        return
    }
    push(.self = $&copied, .value = 30, .allocator = allocator)

    if length(.self = &arr).count != 2 {
        status_code = 1
        return
    }

    if length(.self = &copied).count != 3 {
        status_code = 2
        return
    }

    first_result ::= get(.self = &arr, .index = 0).result
    if is(.value = first_result, .variant = ..error) {
        status_code = 3
        return
    }
    if first_result ..ok != 10 {
        status_code = 3
        return
    }

    copied_first_result ::= get(.self = &copied, .index = 0).result
    if is(.value = copied_first_result, .variant = ..error) {
        status_code = 4
        return
    }
    if copied_first_result ..ok != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
