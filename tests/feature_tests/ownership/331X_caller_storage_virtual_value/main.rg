Source: Abstract = (read(.self: &Self) -> (.result: Int32))

Local: Type = (.value: Int32)

Local implements Source

read(.self: &Local) -> (.result: Int32) := { result = self&.value }

make() -> (.result: Virtual#(.abstract: Source)) := {
    local :: Local = (.value = 29)
    result = to_virtual#(.abstract: Source)(.value = &local)
}

main() -> (.status_code: Int32 = 0) := {
    source ::= make()
    if read(.self = &source) != 29 { status_code = 1 }
}
