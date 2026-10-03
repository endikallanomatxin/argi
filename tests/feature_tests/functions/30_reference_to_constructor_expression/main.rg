Box : Type = (.counter: $&Int32, .created: $&Int32)
NumberBox : Type = (.value: Int32)

Box init(.counter: $&Int32, .created: $&Int32) -> (.result: Box) := {
    result.counter = counter
    result.created = created
    created& = created& + 1
}

deinit(.self: $&Box) -> () := {
    self&.counter& = self&.counter& + 1
}

positive(.box: $&Box) -> (.result: Bool) := {
    result = box&.counter& < 3
}

read(.number: &Int32) -> (.result: Int32) := {
    result = number&
}

read_mut(.number: $&Int32) -> (.result: Int32) := {
    result = number&
}

main() -> (.status_code: Int32 = 0) := {
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
