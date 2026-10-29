main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.length = 6))
    zero :: UIntNative = 0
    one :: UIntNative = 1
    two :: UIntNative = 2
    three :: UIntNative = 3
    four :: UIntNative = 4
    five :: UIntNative = 5

    h :: UInt8 = 104
    e :: UInt8 = 101
    l :: UInt8 = 108
    o :: UInt8 = 111
    bang :: UInt8 = 33

    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = zero, .byte = h))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = one, .byte = e))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = two, .byte = l))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = three, .byte = l))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = four, .byte = o))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = five, .byte = bang))

    view ::= view(.self = &text)
    hello ::= unwrap_or_abort(.value = slice(.self = view, .start = 0, .count = 5))
    hello_again ::= unwrap_or_abort(.value = slice(.self = view, .start = 0, .count = 5))

    if equals(.left = hello, .right = hello_again).ok {
    } else {
        status_code = 1
        return
    }

    if equals(.left = hello, .right = "hello").ok {
    } else {
        status_code = 2
        return
    }

    if equals(.left = hello, .right = "help").ok {
        status_code = 3
        return
    }

    if hello == "hello" {
    } else {
        status_code = 4
        return
    }

    if hello != "help" {
    } else {
        status_code = 5
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
