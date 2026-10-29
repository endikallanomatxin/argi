Counter := (.value: Int32)

Owner := (.value: Int32, .counter: $&Counter)

add_count := (.amount: Int32, .counter: $&Counter) -> () {
    counter&.value = counter&.value + amount
}

observe := (.self: $&Owner) -> () {
    add_count(.amount = self&.value, .counter = self&.counter)
}

implement Deinit#(Owner) (.deinit = observe)

create := (.counter: $&Counter) -> () {
    assume counter
    value ::= Owner(.value = 3, .counter = counter)
    observe($&value)
    if value.value != 3 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    counter ::= Counter(0)
    create($&counter)
    if counter.value != 6 { abort }
}
