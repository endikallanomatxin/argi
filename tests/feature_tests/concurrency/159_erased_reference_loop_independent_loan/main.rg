Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: &Int32)
        where { reads(self) depends_on(result, self) }
)
Provider := (.value: &Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: &Int32) { result = self&.value }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    original :: Int32 = 7
    provider ::= Provider(&original)
    source ::= Virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    count :: Int32 = 0
    while count < 3 {
        if read(reference) != 7 { abort }
        count = count + 1
    }
    _ = unwrap_or_abort(.value = await($&future))
    if later != 42 { abort }
}
