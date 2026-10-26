Counter := (.value: Int32)

Owner := (.value: Int32)

add_count := (.amount: Int32, .counter: $&Counter = reach counter) -> () {
    counter&.value = counter&.value + amount
}

observe := (.self: $&Owner) -> () { add_count(.amount = self&.value) }

implement Deinit<Owner> (.deinit = observe)

create := (.counter: $&Counter) -> () {
    assume counter
    value ::= Owner(3)
    observe($&value)
    if value.value != 3 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    counter ::= Counter(0)
    create($&counter)
    if counter.value != 6 { abort }
}
