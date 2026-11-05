Args := (.value: $&Int32)
Provider := (.marker: Int32)
Operation#(.T: Type): Contract = (
    .run: (.self: &T, .args: Args) -> () where no_access()
)
set := (.value: $&Int32) -> () { value& = 42 }
helper := (.args: Args) -> () { set(args.value) }
implement Operation#(Provider) (
    .run = (.self: &Provider, .args: Args) -> () { helper(args) }
)
main := () -> () {
    provider ::= Provider(0)
    operation ::= to_virtual#(Operation)(&provider)
    value :: Int32 = 7
    Operation#().run(&operation, Args($&value))
}
