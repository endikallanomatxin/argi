Pair: Type = (.first: Int32, .second: (.value: Int32))

read := (.value: Pair) -> (.result: Int32) {
    result = value.first + value.second.value
}

probe := () -> (.result: Int32) {
    pair :: Pair
    pair.first = 40
    pair.second.value = 2
    complete ::= pair
    borrowed ::= &pair
    if borrowed&.second.value != 2 { abort }
    result = read(.value = complete)
}

main := () -> (.status_code: Int32) {
    if #run () -> (.value: Int32) { value = probe() } != 42 { abort }
    #if probe() == 42 { status_code = probe() } else { abort }
}
