UnknownRead#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where {}
)
PureRead#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where { no_access() }
)
Provider := (.marker: Int32)
implement UnknownRead#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) { result = 42 }
)
implement PureRead#(Provider) (
    .get = (.self: &Provider) -> (.result: Int32) {
        unknown ::= Virtual#(UnknownRead)(self)
        result = UnknownRead#().get(.self = &unknown)
    }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    pure ::= Virtual#(PureRead)(&provider)
    _ = PureRead#().get(.self = &pure)
}
