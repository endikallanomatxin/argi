Args := (.value: Int32 = 42)

read_value := Args -> (.result: Int32) { result = value }
read_alias := read_value

acquire := once Args -> (.result: Int32) { result = value }
acquire_alias := acquire

known ::= #run () -> (.result: Int32) { result = read_alias() }

main := () -> (.status_code: Int32) {
    local_alias := read_alias
    from_global ::= read_alias(.value = 7)
    from_local ::= local_alias()
    if known != 42 or from_global != 7 or from_local != 42 { abort }
    status_code = acquire_alias()
}
