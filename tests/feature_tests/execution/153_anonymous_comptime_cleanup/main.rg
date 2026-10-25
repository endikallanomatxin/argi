Counter: Type = (.count: Int32)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

leave_scope(.counter: $&Counter) -> () := {
    owner :: Resource = (.counter = counter)
    return
}

calculate() -> (.result: Int32) := {
    counter :: Counter = (.count = 39)
    {
        first :: Resource = (.counter = $&counter)
        second :: Resource = (.counter = $&counter)
    }
    leave_scope(.counter = $&counter)
    result = counter.count
}

main() -> (.status_code: Int32) := {
    answer ::= #run () -> (.result: Int32) { result = calculate() }
    if calculate() != answer { abort }
    #run {
        counter :: Counter = (.count = 0)
        { owner :: Resource = (.counter = $&counter) }
        if counter.count != 1 { abort }
    }
    status_code = answer
}
