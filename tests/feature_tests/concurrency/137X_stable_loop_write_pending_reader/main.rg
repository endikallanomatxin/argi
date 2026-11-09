read := (.value: &Int32) -> (.result: Int32) { result = value& }
write := (.value: $&Int32) -> () { value& = 42 }
loop_read := (.value: &Int32, .count: UIntNative) -> (.result: Int32 = 0) {
    index :: UIntNative = 0
    while index < count {
        result = result + value&
        index = index + 1
    }
}
loop_write := (.value: $&Int32) -> () {
    index :: UIntNative = 0
    while index < 2 {
        value& = 42
        index = index + 1
    }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 21
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    loop_write($&value)
    _ = unwrap_or_abort(.value = await($&future))
}
