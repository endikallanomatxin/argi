Source: Abstract = (read(.self: &Self) -> (.result: &Int32))

Local: Type = ()

Local implements Source

read(.self: &Local) -> (.result: &Int32) := {
    value ::= 17
    result = &value
}

main() -> (.status_code: Int32 = 0) := {
    local :: Local = ()
    source ::= to_virtual#(.abstract: Source)(.value = &local)
    reference ::= read(.self = &source)
    status_code = reference&
}
