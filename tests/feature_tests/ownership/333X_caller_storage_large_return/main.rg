make() -> (.result: (.reference: &Int32, .values: [128]Int32)) := {
    local ::= 31
    result = (.reference = &local, .values = zeroed#(.t: [128]Int32)())
}

main() -> (.status_code: Int32 = 0) := {
    value ::= make()
    if value.reference&!= 31 or value.values[127] != 0 { status_code = 1 }
}
