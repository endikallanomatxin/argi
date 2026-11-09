Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: &[2]Int32)
        where { reads(self) depends_on(result, self) }
)
Provider := (.value: &[2]Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: &[2]Int32) { result = self&.value }
)
select := (.array: &[2]Int32, .index: UIntNative) -> (.result: &Int32) {
    result = &array&[index]
}
retype := (.base: &Int32) -> (.result: &UInt32) {
    result = trusted_reinterpret_reference#(.from: Int32, .to: UInt32)(.base = base)
}
maybe_retype := (.base: &Int32, .other: &Int32, .enabled: Bool) -> (.result: Errable#(&UInt32, (..disabled))) {
    if enabled == false {
        result = ..ok retype(.base = other)
        return
    }
    result = ..ok retype(.base = base)
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    storage :: [2]Int32 = (7, 9)
    provider ::= Provider(&storage)
    source ::= Virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    first ::= select(.array = reference, .index = 0)
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    element ::= unwrap_or_abort(.value = maybe_retype(.base = first, .other = &later, .enabled = false))
    if element& != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
