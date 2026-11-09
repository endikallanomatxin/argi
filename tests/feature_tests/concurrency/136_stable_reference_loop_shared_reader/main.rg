read := (.value: &Int32) -> (.result: Int32) { result = value& }
write := (.value: $&Int32) -> () { value& = 42 }
loop_read := (.value: &Int32, .count: UIntNative) -> (.result: Int32 = 0) {
    index :: UIntNative = 0
    while index < count {
        result = result + value&
        index = index + 1
    }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 21
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if loop_read(&value, 2) != 42 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
