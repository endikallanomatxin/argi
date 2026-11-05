Work#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .read_value: &Int32, .write_value: $&Int32, .executor: Virtual#(Executor)) -> () where {
        invalidates(write_value)
    }
)
Provider := (.marker: Int32)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
implement Work#(Provider) (
    .run = (.self: &Provider, .read_value: &Int32, .write_value: $&Int32, .executor: Virtual#(Executor)) -> () {
        future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = read_value), .executor = executor))
        write_value& = 7
        _ = unwrap_or_abort(.value = await($&future))
    }
)
main := () -> () {
    provider: Provider = (.marker = 0)
    work ::= to_virtual#(Work)(&provider)
}
