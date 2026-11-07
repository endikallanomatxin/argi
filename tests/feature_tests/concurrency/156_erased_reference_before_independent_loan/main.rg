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
    assume executor ::= to_virtual#(Executor)($&executor_provider)
    original :: Int32 = 7
    provider ::= Provider(&original)
    source ::= to_virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    if read(reference) != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if later != 42 { abort }
}
