AccessCell#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .value: &Int32) -> (.result: Int32) where { writes(value) }
)
Provider := (.marker: Int32)
implement AccessCell#(Provider) (
    .get = (.self: &Provider, .value: &Int32) -> (.result: Int32) { result = value& }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    cell ::= Virtual#(AccessCell)(&provider)
    value :: Int32 = 42
    _ = AccessCell#().get(.self = &cell, .value = &value)
}
