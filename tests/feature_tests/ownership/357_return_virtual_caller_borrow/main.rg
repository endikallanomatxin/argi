Source: Abstract = (read(.self: &Self) -> (.result: Int32))

Local: Type = (.value: Int32)

Local implements Source

read(.self: &Local) -> (.result: Int32) := {
    result = self&.value
}

make(.local: &Local) -> (.result: Virtual#(Source)) := {
    result = to_virtual#(Source)(local)
}

main() -> (.status_code: Int32 = 0) := {
    local ::= Local(29)
    source ::= make(&local)

    if read(&source) != 29 { status_code = 1 }
}
