Project#(.Provider: Type): Contract = (
    .reference: (.self: &Provider, .value: $&Int32) -> (.result: &Int32) where {
        no_access()
        depends_on(result, value)
    }
)
Provider := (.marker: Int32)
implement Project#(Provider) (
    .reference = (.self: &Provider, .value: $&Int32) -> (.result: &Int32) {
        result = read_reference#(Int32)(.base = value).reference
    }
)
write := (.value: $&Int32) -> (.result: Int32) { value& = 42 result = value& }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    provider: Provider = (.marker = 0)
    projection ::= Virtual#(Project)(&provider)
    value :: Int32 = 7
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    reference ::= Project#().reference(.self = &projection, .value = $&value)
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
    if reference& != 42 { abort }
}
