read := (.value: &Int32) -> (.result: Int32) { result = value& }
write := (.value: $&Int32) -> () { value& = 42 }
loop_read := (.value: &Int32, .count: UIntNative) -> (.result: Int32 = 0) {
    index :: UIntNative = 0
    while index < count {
        result = result + value&
        index = index + 1
    }
}
route := (.first: &Int32, .second: &Int32) -> (.result: Int32 = 0) {
    cursor :: &Int32 = first
    index :: UIntNative = 0
    while index < 2 {
        result = result + cursor&
        cursor = second
        index = index + 1
    }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    first :: Int32 = 7
    second :: Int32 = 9
    if route(&first, &second) != 16 { abort }
    a ::= $&first
    b ::= $&first
    index :: UIntNative = 0
    while index < 2 {
        a& = b& + 1
        index = index + 1
    }
    if first != 9 { abort }
}
