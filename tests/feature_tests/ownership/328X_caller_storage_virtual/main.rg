Source#(.Participant: Type): Contract = (.read: (.self: &Participant) -> (.result: &Int32) where depends_on(result, self))

Local: Type = ()

implement Source#(Local) (.read = _impl_read_Local)

_impl_read_Local := (.self: &Local) -> (.result: &Int32)  {
    value ::= 17
    result = &value
}

main() -> (.status_code: Int32 = 0) := {
    local :: Local = ()
    source ::= to_virtual#(.abstract: Source)(.value = &local)
    reference ::= read(.self = &source)
    status_code = reference&
}
