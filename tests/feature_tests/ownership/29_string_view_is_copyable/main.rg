measure(.view: StringView) -> (.count: UIntNative) := {
    count = view.length
}

main(.system: System) -> (.status_code: Int32) := {
    text ::= String(.length = 4)
    bytes_set(.string = $&text, .index = 0, .value = 65)
    bytes_set(.string = $&text, .index = 1, .value = 114)
    bytes_set(.string = $&text, .index = 2, .value = 103)
    bytes_set(.string = $&text, .index = 3, .value = 105)

    first_view ::= as_view(.self = &text)
    second_view : StringView = first_view

    if measure(.view = second_view).count != 4 {
        status_code = 1
        deinit(.self = $&text, .allocator = system.allocator)
        return
    }

    deinit(.self = $&text, .allocator = system.allocator)
    status_code = 0
}
