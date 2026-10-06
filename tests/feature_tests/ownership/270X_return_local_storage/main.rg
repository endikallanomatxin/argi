local_pointer() -> (.result: &Int32) := {
    local ::= 1
    result = &local
}

main() -> (.status_code: Int32 = 0) := {
    pointer ::= local_pointer().result
    status_code = pointer&
}
