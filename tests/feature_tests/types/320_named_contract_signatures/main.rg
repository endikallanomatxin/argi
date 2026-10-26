Input := (.source: &Bool)

Output := (.value: &Bool, .ready: Bool)

Observe<.Participant: Type>: Contract = (
    .observe : Input -> Output where { depends_on(value, source) }
)

Owner := (.unused: Bool)

implement Observe<Owner> (
    .observe = Input -> Output {
        value = source
        ready = true
    }
)

Args := <.T: Type> (.owner: &T, .flag: Bool)

Read<.Participant: Type>: Contract = (
    .read_flag : Args<Participant> -> (.result: Bool) where { depends_on(result, flag) }
)

implement Read<Owner> (
    .read_flag = Args<Owner> -> (.result: Bool) { result = flag }
)

computed ::= #run () -> (.result: Bool) {
    flag: Bool = true
    outputs: Output = Observe<Owner>.observe(.source = &flag)
    owner: Owner = (.unused = false)
    handle ::= to_virtual<.contract: Read>(.value = &owner)
    result = [
        outputs.ready
        and outputs.value&
        and read_flag(.owner = &handle, .flag = true).result
    ]
}

main := () -> () {
    flag: Bool = true
    outputs: Output = Observe<Owner>.observe(.source = &flag)
    owner: Owner = (.unused = false)
    handle ::= to_virtual<.contract: Read>(.value = &owner)
    if read_flag(.owner = &handle, .flag = true).result {} else { abort }
    if outputs.ready and outputs.value&and read_flag(.owner = &owner, .flag = true).result {
    } else {
        abort
    }
    if computed {} else { abort }
}
