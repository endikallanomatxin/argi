Input := (.source: &Bool)

Output := (.value: &Bool, .ready: Bool)

Observe#(.Participant: Type): Contract = (
    .observe : Input -> Output where { depends_on(value, source) }
)

Owner := (.unused: Bool)

implement Observe#(Owner) (
    .observe = Input -> Output {
        value = source
        ready = true
    }
)

Args := <.T: Type> (.owner: &T, .flag: Bool)

Read#(.Participant: Type): Contract = (
    .read_flag : Args<Participant> -> (.result: Bool)
)

implement Read#(Owner) (
    .read_flag = Args<Owner> -> (.result: Bool) { result = flag }
)

main := () -> () {
    outputs: Output
    {
        local: Bool = true
        outputs = Observe<Owner>.observe(.source = &local)
    }
    if outputs.value&{ abort }
}
