set_number := (.destination: $&Int32) -> () {
    destination&= 42
}

probe := () -> (.result: Int32) {
    number :: Int32
    set_number(.destination = $&number)
    result = number
}

main := () -> (.status_code: Int32) {
    if #run () -> (.value: Int32) { value = probe() } != 42 { abort }
    #if probe() == 42 { status_code = probe() } else { abort }
}
