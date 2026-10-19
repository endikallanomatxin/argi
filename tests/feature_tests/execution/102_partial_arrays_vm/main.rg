set_number := (.destination: $&Int32, .value: Int32) -> () {
    destination&= value
}

probe := () -> (.result: Int32) {
    numbers :: [2]Int32
    numbers[0] = 40
    first ::= numbers[0]
    numbers[1] = 2
    complete ::= numbers
    nested :: [2](.value: Int32)
    nested[0].value = first
    set_number(.destination = $&nested[1].value, .value = complete[1])
    nested_complete ::= nested
    result = nested_complete[0].value + nested_complete[1].value
}

main := () -> (.status_code: Int32) {
    if #run probe() != 42 { abort }
    #if probe() == 42 { status_code = probe() } else { abort }
}
