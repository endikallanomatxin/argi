Echo#(.Participant: Type): Contract = (
    .echo: (.self: &Participant, .input: Int32) -> (.output: Int32) where depends_on(output, input)
)

Direct: Type = (.marker: Int32)

Moved: Type = (.marker: Int32)

implement Echo#(Direct) (.echo = _impl_echo_Direct)
implement Echo#(Moved) (.echo = _impl_echo_Moved)

_impl_echo_Direct := (.self: &Direct, .input: Int32) -> (.output: Int32)  {
    output = input
}

_impl_echo_Moved := (.self: &Moved, .input: Int32) -> (.output: Int32)  {
    output = ~input
}

register_moved(.value: $&Moved) -> () := {
    unused ::= to_virtual#(.contract: Echo)(.value = value)
}

main() -> (.status_code: Int32 = 0) := {
    moved :: Moved = (.marker = 0)
    register_moved(.value = $&moved)
    direct :: Direct = (.marker = 0)
    virtual ::= to_virtual#(.contract: Echo)(.value = $&direct)
    echoed ::= echo(.self = &virtual, .input = 7)
    if echoed != 7 { status_code = 1 }
}
