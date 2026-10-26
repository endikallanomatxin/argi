main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    maximum :: UIntNative = 0
    bytes ::= size_of(.type = UIntNative)
    index :: UIntNative = 0
    while index < bytes {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    text ::= format(.value = maximum)!!!
    parsed ::= parse_uintnative(.text = view(.self = &text))!!!
    if parsed != maximum { abort }
    if parse_uintnative(.text = "+00042")!!! != 42 { abort }
    if parse_uintnative(.text = "ff", .base = 16)!!! != 255 { abort }
    match parse_uintnative(.text = "18446744073709551616") {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_range { abort } }
    }
    match parse_uintnative(.text = "-1") {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    match parse_uintnative(.text = "1", .base = 1) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_base { abort } }
    }
    status_code = 0
}
