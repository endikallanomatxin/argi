main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.length = 6)
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

    bytes_set(.string = $&text, .index = zero, .value = h)
    bytes_set(.string = $&text, .index = one, .value = e)
    bytes_set(.string = $&text, .index = two, .value = l)
    bytes_set(.string = $&text, .index = three, .value = l)
    bytes_set(.string = $&text, .index = four, .value = o)
    bytes_set(.string = $&text, .index = five, .value = bang)

    view ::= as_view(.self = &text)
    hello : StringView = (
        .data = view.data,
        .length = 5,
    )
    hello_again : StringView = (
        .data = view.data,
        .length = 5,
    )

    if equals(.left = &hello, .right = &hello_again).ok {
    } else {
        status_code = 1
        return
    }

    if equals(.left = &hello, .right = "hello").ok {
    } else {
        status_code = 2
        return
    }

    if equals(.left = &hello, .right = "help").ok {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
