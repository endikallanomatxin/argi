Payload := (.bytes: [65]UInt8, .marker: UIntNative)

large := (.seed: UInt8) -> (.result: Payload) {
    result = (.bytes = zeroed#([65]UInt8)(), .marker = 99)
    index :: UIntNative = 0
    while index < 65 {
        result.bytes[index] = seed
        index = index + 1
    }
}

floating := (.value: Float64) -> (.result: Float64) { result = value * 2.0 }
empty := () -> () {}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(large)(.args = (.seed = 42)))
    value ::= unwrap_or_abort(.value = await($&future))
    if value.marker != 99 { abort }
    index :: UIntNative = 0
    while index < 65 {
        if value.bytes[index] != 42 { abort }
        index = index + 1
    }
    numeric ::= unwrap_or_abort(.value = async#(floating)(.args = (.value = 21.0)))
    if unwrap_or_abort(.value = await($&numeric)) != 42.0 { abort }
    nothing ::= unwrap_or_abort(.value = async#(empty)(.args = ()))
    _ = unwrap_or_abort(.value = await($&nothing))
}
