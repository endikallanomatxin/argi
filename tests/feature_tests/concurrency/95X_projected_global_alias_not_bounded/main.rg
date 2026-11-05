State := (.first: Int32, .second: Int32)
global: State = (.first = 0, .second = 0)
Update#(.Provider: Type): Contract = (
    .set: (.self: &Provider, .value: $&State, .use_global: Bool) -> () where {
        reads(value)
        writes(value.first)
    }
)
Provider := (.marker: Int32)
implement Update#(Provider) (
    .set = (.self: &Provider, .value: $&State, .use_global: Bool) -> () {
        alias := value
        if use_global { alias = $&global }
        alias&.first = 42
    }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    value: State = (.first = 0, .second = 0)
    Update#(Provider).set(.self = &provider, .value = $&value, .use_global = false)
}
