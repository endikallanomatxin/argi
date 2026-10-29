drops :: Int32 = 0

Resource := (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

references := (.first: $&Resource, .second: $&Resource) -> (.result: [2] $&Resource) {
    result = (first, second)
}

replace := (.targets: [2] $&Resource) -> () {
    targets[0]&= Resource(.value = 9)
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    {
        first :: Resource = Resource(.value = 1)
        second :: Resource = Resource(.value = 2)
        targets ::= references(.first = $&first, .second = $&second)
        replace(.targets = targets)
        if targets[0]&.value != 9 or targets[1]&.value != 2 { abort }
        if first.value != 9 or second.value != 2 { abort }
    }
    if drops != 3 { abort }
    status_code = 42
}
