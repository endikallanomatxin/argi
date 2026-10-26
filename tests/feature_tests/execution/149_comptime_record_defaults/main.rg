record_width := <.T: Type> () -> (.count: UIntNative) { count = size_of(.type = T) }

read_default := <.T: Type> (.value: T) -> (.result: Int32) {
    #if record_width<.T: T>() > 0 {
        result = value.extra.left + value.extra.right
    } #else {
        result = 0
    }
}

with_default := <.T: Type, .n: Int32> (.value: T) -> (.result: Int32) {
    result = read_default<
        .T : (.item: T, .extra: (.left: Int32, .right: Int32) = (.left = n, .right = 25))
    >(.value = (.item = value))
}

main := () -> (.status_code: Int32) {
    if with_default<.T: Int32, .n = 17>(.value = 7) != 42 { abort }
    if with_default<.T: Bool, .n = 16>(.value = true) != 41 { abort }
    if [
        [#run () -> (.value: Int32) { value = with_default<.T: Int32, .n = 17>(.value = 9) }]
        != 42
    ] { abort }
    status_code = 42
}
