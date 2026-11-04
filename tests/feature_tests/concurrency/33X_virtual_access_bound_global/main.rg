PureValue#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { no_access() }
)
Provider := (.marker: Int32)
global :: Int32 = 42
implement PureValue#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = global }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    pure ::= to_virtual#(PureValue)(&provider)
    _ = PureValue#().get(.self = &pure)
}
