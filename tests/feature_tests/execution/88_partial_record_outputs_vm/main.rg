set_number := (.destination: $&Int32, .value: Int32) -> () {
    destination&= value
}

Pair: Type = (.first: Int32, .second: (.value: Int32))

read_first := (.pair: &Pair) -> (.result: Int32) {
    result = pair&.first
}

make := () -> (.result: Pair) {
    result.first = 41
    set_number(.destination = $&result.second.value, .value = [read_first(.pair = &result) + 1])
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run () -> (.value: Pair) { value = make() }
    if compiled.second.value != 42 { abort }
    #if make().second.value == 42 {
        status_code = make().second.value
    } else {
        abort
    }
}
