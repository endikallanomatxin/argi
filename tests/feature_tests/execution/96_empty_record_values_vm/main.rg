Empty: Type = ()

Packet: Type = (.empty: Empty, .value: Int32)

make_empty := () -> (.result: Empty) {
    result = Empty()
}

make := () -> (.result: Packet) {
    result.empty = make_empty()
    result.value = 42
}

main := () -> (.status_code: Int32) {
    empty ::= #run make_empty()
    compiled ::= #run make()
    if compiled.value != 42 { abort }
    #if make().value == 42 {
        status_code = make().value
    } else {
        abort
    }
}
