Resource: Type = (.active: Bool)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

produce := (.state: $&(.used: Bool)) -> (.result: Resource) {
    if state&.used {
        result = (.active = false)
    } else {
        state&.used = true
        result = (.active = true)
    }
}

observe := (.value: &Resource) -> (.result: Bool) {
    result = value&.active
}

exercise := () -> (.result: Int32) {
    state :: (.used: Bool) = (.used = false)
    while observe(.value = &produce(.state = $&state)) {}
    if state.used == false { abort }
    result = 42
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run exercise()
    if compiled != 42 { abort }
    #if exercise() == 42 {
        status_code = exercise()
    } else {
        abort
    }
}
