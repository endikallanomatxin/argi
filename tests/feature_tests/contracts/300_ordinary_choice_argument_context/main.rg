Mode: Type = (..read, ..write)

implement ImplicitlyCopyable<Mode> ()

read_mode := (.mode: Mode) -> (.ok: Bool) {
    ok = is(.value = mode, .variant = ..read)
}

optional_byte := (.value: ?UInt8) -> (.byte: UInt8) {
    match value {
        ..none { byte = 0 }
        ..some payload { byte = payload.value }
    }
}

check_modes := <.Marker: Type> (.marker: Marker) -> (.ok: Bool) {
    named ::= read_mode(.mode = ..read)
    positional ::= read_mode(..write)
    payload ::= optional_byte(.value = ..some(.value = 250))
    empty ::= optional_byte(..none)
    ok = named and positional == false and payload == 250 and empty == 0
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    if check_modes(.marker = 1) == false { status_code = 1 }
    marker: UInt8 = 2
    if check_modes(.marker = marker) == false { status_code = 2 }
}
