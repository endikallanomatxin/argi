Args := (.value: Int32)
Provider := (.marker: Int32)
Operation#(.T: Type): Contract = (
    .run: (.self: &T, .args: Args) -> (.result: Int32) where no_access()
)
set := (.value: $&Int32) -> () { value& = 42 }
helper := (.args: Args) -> (.result: Int32) {
    set($&args.value)
    result = args.value
}
implement Operation#(Provider) (
    .run = (.self: &Provider, .args: Args) -> (.result: Int32) { result = helper(args) }
)
main := () -> () {
    provider ::= Provider(0)
    operation ::= Virtual#(Operation)(&provider)
    args ::= Args(7)
    if Operation#().run(&operation, args) != 42 { abort }
    if args.value != 7 { abort }
}
