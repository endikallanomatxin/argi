state :: Int32 = 0
Args := (.value: $&Int32)
Provider := (.marker: Int32)
Operation#(.T: Type): Contract = (
    .run: (.self: &T, .args: Args, .global: Bool) -> () where writes(args.value)
)
set := (.value: $&Int32) -> () { value& = 42 }
helper := (.args: Args, .global: Bool) -> () {
    target: $&Int32 = args.value
    if global { target = $&state }
    set(target)
}
implement Operation#(Provider) (
    .run = (.self: &Provider, .args: Args, .global: Bool) -> () { helper(args, global) }
)
main := () -> () {
    provider ::= Provider(0)
    operation ::= to_virtual#(Operation)(&provider)
    value :: Int32 = 7
    Operation#().run(&operation, Args($&value), true)
}
