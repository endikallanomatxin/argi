Resource := (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

observe := (.targets: [2] $&Resource) -> () {
    saved ::= targets
    deinit(.self = targets[0])
    targets[0]&= Resource(.value = 9)
    if saved[0]&.value == 0 { abort }
}

main := () -> (.status_code: Int32) {
    first :: Resource = Resource(.value = 1)
    second :: Resource = Resource(.value = 2)
    observe(.targets = ($&first, $&second))
    status_code = 42
}
