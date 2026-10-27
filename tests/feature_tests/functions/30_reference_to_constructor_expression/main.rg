Box := (.counter: $&Int32, .created: $&Int32)

NumberBox := (.value: Int32)

BoxInitArgs: Type = (.counter: $&Int32, .created: $&Int32)

implement Init#(Box, BoxInitArgs) (
    .Result : Type = Box

    .init = BoxInitArgs -> (.result: Result) {
        _init_counter ::= ~counter
        _init_created ::= ~created

        result.counter = _init_counter
        result.created = _init_created
        _init_created&= _init_created&+ 1
    }
)

implement Deinit#(Box) (
    .deinit = (.self: $&Box) -> () {
        self&.counter&= self&.counter&+ 1
    }
)

positive := (.box: $&Box) -> (.result: Bool) {
    result = box&.counter&< 3
}

read := (.number: &Int32) -> (.result: Int32) {
    result = number&
}

read_mut := (.number: $&Int32) -> (.result: Int32) {
    result = number&
}

main := () -> (.status_code: Int32 = 0) {
    count ::= 0
    created ::= 0
    if read(.number = &7).result != 7 { status_code = 4 }
    if read_mut(.number = $&NumberBox(.value = 9).value).result != 9 { status_code = 5 }
    {
        number ::= $&NumberBox(.value = 11)
        if number&.value != 11 { status_code = 6 }
    }
    if false and positive(.box = $&Box(.counter = $&count, .created = $&created)) {
        status_code = 1
    }
    if count != 0 or created != 0 { status_code = 2 }

    i ::= 0
    {
        while i < 3 and positive(.box = $&Box(.counter = $&count, .created = $&created)) {
            i = i + 1
        }
    }
    if count != 3 or created != 3 { status_code = 3 }
}
